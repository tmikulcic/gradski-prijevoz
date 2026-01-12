const API_BASE = "http://localhost:3000/api";

const el = (id) => document.getElementById(id);

async function api(path, options) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
  return data;
}

function showError(msg) {
  const box = el("error");
  box.textContent = msg;
  box.classList.remove("hidden");
}
function clearError() {
  const box = el("error");
  box.textContent = "";
  box.classList.add("hidden");
}

function badge(text, type) {
  return `<span class="badge badge--${type}">${text}</span>`;
}

function badgeComplaint(s) {
  if (s === "Riješeno") return badge(s, "green");
  if (s === "U obradi") return badge(s, "orange");
  if (s === "Odbačeno") return badge(s, "red");
  return badge(s || "Novo", "gray");
}

function badgeFine(s) {
  if (s === "Plaćeno") return badge(s, "green");
  if (s === "U postupku") return badge(s, "orange");
  return badge(s || "Neplaćeno", "red");
}

function fmt(v) {
  if (!v) return "";
  return String(v).replace("T", " ").replace(".000Z", "");
}

function truncate(s, n = 80) {
  const t = String(s || "");
  if (t.length <= n) return t;
  return t.slice(0, n - 1) + "…";
}

function wireTabs() {
  const tabs = Array.from(document.querySelectorAll(".tab"));
  tabs.forEach((t) => {
    t.onclick = () => {
      tabs.forEach((x) => x.classList.remove("active"));
      t.classList.add("active");
      const id = t.getAttribute("data-tab");
      for (const p of document.querySelectorAll(".panel")) p.classList.add("hidden");
      el(`panel-${id}`).classList.remove("hidden");
    };
  });
}

async function loadDashboard() {
  const d = await api("/ops/dashboard");
  el("dVozilaPromet").textContent = String(d.vozila?.u_prometu ?? 0);
  el("dVozilaMeta").textContent = `Van prometa: ${d.vozila?.van_prometa ?? 0} / Ukupno: ${d.vozila?.ukupno ?? 0}`;

  el("dPrituzbeNovo").textContent = String(d.complaints?.novo ?? 0);
  el("dPrituzbeMeta").textContent = `U obradi: ${d.complaints?.u_obradi ?? 0}`;

  const nepl = Number(d.fines?.neplaceno ?? 0);
  const uPost = Number(d.fines?.u_postupku ?? 0);
  el("dKazneNeplac").textContent = String(nepl + uPost);
  el("dKazneMeta").textContent = `Neplaćeno: ${nepl} / U postupku: ${uPost}`;

  el("dServisiMjesec").textContent = String(d.services?.ovaj_mjesec ?? 0);
  el("dPolasciUkupno").textContent = String(d.timetable?.ukupno_polazaka ?? 0);
}

async function loadLines() {
  const data = await api("/ops/lines");
  const rows = data.rows || [];

  const lineSelect = el("lineSelect");
  lineSelect.innerHTML = "";
  for (const l of rows) {
    const opt = document.createElement("option");
    opt.value = l.id;
    opt.textContent = `${l.oznaka} — ${l.naziv}`;
    lineSelect.appendChild(opt);
  }

  const cLine = el("cLine");
  cLine.innerHTML = "";
  const all = document.createElement("option");
  all.value = "";
  all.textContent = "Sve";
  cLine.appendChild(all);
  for (const l of rows) {
    const opt = document.createElement("option");
    opt.value = l.id;
    opt.textContent = `${l.oznaka} — ${l.naziv}`;
    cLine.appendChild(opt);
  }
}

async function loadTimetable() {
  const lineId = Number(el("lineSelect").value);
  const data = await api(`/ops/timetable?linija_id=${lineId}`);

  const body = el("timetableBody");
  body.innerHTML = "";
  for (const r of data.rows || []) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${r.vrijeme_polaska}</td>
      <td>${r.tip_vozila}</td>
      <td>${r.kalendar_naziv}</td>
    `;
    body.appendChild(tr);
  }

  const sbody = el("stopsBody");
  sbody.innerHTML = "";
  for (const s of data.stops || []) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${s.redoslijed}</td>
      <td>${s.stanica}</td>
      <td>${s.zona_kod}</td>
    `;
    sbody.appendChild(tr);
  }
}

async function loadComplaints() {
  const params = new URLSearchParams();
  if (el("cStatus").value) params.set("status", el("cStatus").value);
  if (el("cCategory").value) params.set("kategorija", el("cCategory").value);
  if (el("cLine").value) params.set("linija_id", el("cLine").value);

  const data = await api(`/ops/complaints?${params.toString()}`);
  const body = el("complaintsBody");
  body.innerHTML = "";

  for (const r of data.rows || []) {
    const line = r.linija_oznaka ? `${r.linija_oznaka} — ${r.linija_naziv}` : "—";
    const user = `${r.korisnik_ime}${r.korisnik_email ? " (" + r.korisnik_email + ")" : ""}`;

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${fmt(r.datum_prituzbe)}</td>
      <td>${line}</td>
      <td>${r.kategorija_prituzbe}</td>
      <td>${user}</td>
      <td>${badgeComplaint(r.status_rjesavanja)}</td>
      <td title="${String(r.tekst_prituzbe || "").replaceAll('"', "&quot;")}">${truncate(r.tekst_prituzbe, 90)}</td>
      <td>
        <select class="input input--small" data-complaint-status data-id="${r.id}">
          <option value="Novo" ${r.status_rjesavanja === "Novo" ? "selected" : ""}>Novo</option>
          <option value="U obradi" ${r.status_rjesavanja === "U obradi" ? "selected" : ""}>U obradi</option>
          <option value="Riješeno" ${r.status_rjesavanja === "Riješeno" ? "selected" : ""}>Riješeno</option>
          <option value="Odbačeno" ${r.status_rjesavanja === "Odbačeno" ? "selected" : ""}>Odbačeno</option>
        </select>
        <button class="btnLink" data-complaint-save data-id="${r.id}" type="button">Spremi</button>
      </td>
    `;
    body.appendChild(tr);
  }

  body.querySelectorAll("[data-complaint-save]").forEach((btn) => {
    btn.onclick = async () => {
      clearError();
      const id = btn.getAttribute("data-id");
      const sel = body.querySelector(`[data-complaint-status][data-id="${id}"]`);
      const status = sel ? sel.value : "";
      try {
        await api(`/ops/complaints/${id}`, { method: "PATCH", body: JSON.stringify({ status_rjesavanja: status }) });
        await loadComplaints();
      } catch (e) {
        showError(e.message);
      }
    };
  });
}

async function loadMaintenance() {
  const params = new URLSearchParams();
  if (el("mType").value) params.set("vrsta", el("mType").value);
  if (el("mFrom").value) params.set("from", el("mFrom").value);
  if (el("mTo").value) params.set("to", el("mTo").value);

  const data = await api(`/ops/maintenance?${params.toString()}`);
  const body = el("maintenanceBody");
  body.innerHTML = "";

  for (const r of data.rows || []) {
    const vehicle = `${r.tip_vozila} • ${r.vrsta_goriva} • ${r.kapacitet_putnika} putnika`;
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${r.datum_servisa}</td>
      <td>${vehicle}</td>
      <td>${r.vrsta_servisa}</td>
      <td>${r.trosak_servisa}</td>
      <td>${r.mehanicar || ""}</td>
      <td title="${String(r.opis_radova || "").replaceAll('"', "&quot;")}">${truncate(r.opis_radova, 90)}</td>
    `;
    body.appendChild(tr);
  }
}

async function loadMaintenanceLookups() {
  const [vehicles, mechanics] = await Promise.all([api("/ops/vehicles"), api("/ops/mechanics")]);

  const vSel = el("amVehicle");
  vSel.innerHTML = "";
  for (const v of vehicles.rows || []) {
    const opt = document.createElement("option");
    opt.value = v.id;
    opt.textContent = `${v.tip_vozila} • ${v.vrsta_goriva} • ${v.kapacitet_putnika} putnika ${v.u_prometu ? "(u prometu)" : "(van prometa)"}`;
    vSel.appendChild(opt);
  }

  const mSel = el("amMechanic");
  mSel.innerHTML = "";
  for (const m of mechanics.rows || []) {
    const opt = document.createElement("option");
    opt.value = m.id;
    opt.textContent = m.label;
    mSel.appendChild(opt);
  }
}

async function saveMaintenance() {
  clearError();
  const payload = {
    vozilo_id: el("amVehicle").value,
    zaposlenik_id: el("amMechanic").value,
    datum_servisa: el("amDate").value,
    vrsta_servisa: el("amType").value,
    trosak_servisa: el("amCost").value,
    opis_radova: el("amDesc").value
  };

  if (!payload.datum_servisa) {
    showError("Odaberi datum servisa.");
    return;
  }
  if (payload.trosak_servisa === "" || payload.trosak_servisa == null) {
    showError("Upiši trošak servisa.");
    return;
  }

  await api("/ops/maintenance", { method: "POST", body: JSON.stringify(payload) });
}

async function loadFines() {
  const params = new URLSearchParams();
  if (el("fStatus").value) params.set("status", el("fStatus").value);
  if (el("fFrom").value) params.set("from", el("fFrom").value);
  if (el("fTo").value) params.set("to", el("fTo").value);

  const data = await api(`/ops/fines?${params.toString()}`);
  const body = el("finesBody");
  body.innerHTML = "";

  for (const r of data.rows || []) {
    const user = `${r.korisnik_ime}${r.korisnik_email ? " (" + r.korisnik_email + ")" : ""}`;
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${fmt(r.datum_prekrsaja)}</td>
      <td>${user}</td>
      <td>${r.iznos_kazne}</td>
      <td>${badgeFine(r.status_placanja)}</td>
      <td title="${String(r.napomena || "").replaceAll('"', "&quot;")}">${truncate(r.napomena, 70)}</td>
      <td>
        <select class="input input--small" data-fine-status data-id="${r.id}">
          <option value="Neplaćeno" ${r.status_placanja === "Neplaćeno" ? "selected" : ""}>Neplaćeno</option>
          <option value="U postupku" ${r.status_placanja === "U postupku" ? "selected" : ""}>U postupku</option>
          <option value="Plaćeno" ${r.status_placanja === "Plaćeno" ? "selected" : ""}>Plaćeno</option>
        </select>
        <button class="btnLink" data-fine-save data-id="${r.id}" type="button">Spremi</button>
      </td>
    `;
    body.appendChild(tr);
  }

  body.querySelectorAll("[data-fine-save]").forEach((btn) => {
    btn.onclick = async () => {
      clearError();
      const id = btn.getAttribute("data-id");
      const sel = body.querySelector(`[data-fine-status][data-id="${id}"]`);
      const status = sel ? sel.value : "";
      try {
        await api(`/ops/fines/${id}`, { method: "PATCH", body: JSON.stringify({ status_placanja: status }) });
        await loadFines();
      } catch (e) {
        showError(e.message);
      }
    };
  });
}

async function init() {
  wireTabs();

  el("refreshAll").onclick = async () => {
    clearError();
    try {
      await Promise.all([loadDashboard(), loadComplaints(), loadMaintenance(), loadFines()]);
    } catch (e) {
      showError(e.message);
    }
  };

  el("loadTimetable").onclick = async () => {
    clearError();
    try {
      await loadTimetable();
    } catch (e) {
      showError(e.message);
    }
  };

  el("loadComplaints").onclick = async () => {
    clearError();
    try {
      await loadComplaints();
    } catch (e) {
      showError(e.message);
    }
  };

  el("loadMaintenance").onclick = async () => {
    clearError();
    try {
      await loadMaintenance();
    } catch (e) {
      showError(e.message);
    }
  };

  el("loadFines").onclick = async () => {
    clearError();
    try {
      await loadFines();
    } catch (e) {
      showError(e.message);
    }
  };

  const modal = el("maintenanceModal");
  el("openAddMaintenance").onclick = async () => {
    clearError();
    try {
      await loadMaintenanceLookups();
      el("amDate").value = new Date().toISOString().slice(0, 10);
      el("amCost").value = "";
      el("amDesc").value = "";
      modal.showModal();
    } catch (e) {
      showError(e.message);
    }
  };

  el("saveMaintenance").onclick = async () => {
    clearError();
    try {
      await saveMaintenance();
      modal.close();
      await loadMaintenance();
      await loadDashboard();
    } catch (e) {
      showError(e.message);
    }
  };

  try {
    await loadLines();
    await loadDashboard();
    if (el("lineSelect").value) await loadTimetable();
    await Promise.all([loadComplaints(), loadMaintenance(), loadFines()]);
  } catch (e) {
    showError(e.message);
  }
}

init();