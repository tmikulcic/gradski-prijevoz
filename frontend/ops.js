const API_BASE = 'http://localhost:3000/api';

const el = (id) => document.getElementById(id);

let COMPLAINTS_BY_ID = new Map();
let OPEN_COMPLAINT_ID = null;

async function api(path, options) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }
  if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
  return data;
}

function showError(msg) {
  const box = el('error');
  box.textContent = msg;
  box.classList.remove('hidden');
}
function clearError() {
  const box = el('error');
  box.textContent = '';
  box.classList.add('hidden');
}

function badge(text, type) {
  return `<span class="badge badge--${type}">${text}</span>`;
}

function badgeComplaint(s) {
  if (s === 'Riješeno') return badge(s, 'green');
  if (s === 'U obradi') return badge(s, 'orange');
  if (s === 'Odbačeno') return badge(s, 'red');
  return badge(s || 'Novo', 'gray');
}

function badgeFine(s) {
  if (s === 'Plaćeno') return badge(s, 'green');
  if (s === 'U postupku') return badge(s, 'orange');
  return badge(s || 'Neplaćeno', 'red');
}

function fmt(v) {
  if (!v) return '';
  return String(v).replace('T', ' ').replace('.000Z', '');
}

function truncate(s, n = 80) {
  const t = String(s || '');
  if (t.length <= n) return t;
  return t.slice(0, n - 1) + '…';
}

/* ===== Pie charts (CSS conic-gradient) ===== */

const PIE_PALETTE = ['#2563eb', '#16a34a', '#f59e0b', '#ef4444', '#64748b', '#a855f7', '#14b8a6', '#f97316'];

function renderPie(pieId, legendId, items) {
  const pie = el(pieId);
  const legend = el(legendId);
  if (!pie || !legend) return;

  const safeItems = (items || [])
    .map((x, i) => ({
      label: String(x.label ?? ''),
      value: Number(x.value ?? 0),
      color: PIE_PALETTE[i % PIE_PALETTE.length],
    }))
    .filter((x) => Number.isFinite(x.value) && x.value > 0);

  const total = safeItems.reduce((a, b) => a + b.value, 0);

  if (!total) {
    pie.style.background = 'conic-gradient(#e5e7eb 0 100%)';
    legend.innerHTML = '<div class="muted">Nema podataka</div>';
    return;
  }

  let acc = 0;
  const stops = safeItems.map((s) => {
    const start = acc;
    acc += s.value;
    const from = (start / total) * 100;
    const to = (acc / total) * 100;
    return `${s.color} ${from}% ${to}%`;
  });

  pie.style.background = `conic-gradient(${stops.join(', ')})`;

  legend.innerHTML = safeItems
    .map((s) => {
      const p = Math.round((s.value / total) * 100);
      return `
        <div class="legendItem">
          <div class="legendLeft">
            <span class="dot" style="background:${s.color}"></span>
            <span class="legendLabel">${s.label}</span>
          </div>
          <div class="legendValue">${p}%</div>
        </div>
      `;
    })
    .join('');
}

async function loadDashboard() {
  const d = await api('/ops/dashboard');

  const inTraffic = Number(d.vozila?.u_prometu ?? 0);
  const total = Number(d.vozila?.ukupno ?? 0);
  const out = Number(d.vozila?.van_prometa ?? 0);

  const c = d.charts || {};
  renderPie('pieVehiclesFuel', 'legendVehiclesFuel', c.vozila_po_gorivu);
  renderPie('pieComplaintsStatus', 'legendComplaintsStatus', c.prituzbe_po_statusu);
  renderPie('pieComplaintsCategory', 'legendComplaintsCategory', c.prituzbe_po_kategoriji);
  renderPie('pieFinesStatus', 'legendFinesStatus', c.prekrsaji_po_statusu);
  renderPie('pieServicesType', 'legendServicesType', c.servisi_po_vrsti);
  renderPie('pieEmployeesRole', 'legendEmployeesRole', c.zaposlenici_po_ulozi);
  renderPie('pieTicketsType', 'legendTicketsType', c.prodane_karte_po_tipu);
  renderPie('pieVehiclesTraffic', 'legendVehiclesTraffic', [
  { label: 'U prometu', value: inTraffic },
  { label: 'Van prometa', value: out }
]);
}

function setPie(pieId, segments) {
  const pie = el(pieId);
  if (!pie) return;

  const safe = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : 0;
  };

  const segs = segments.map((s) => ({
    value: safe(s.value),
    color: s.color,
  }));

  const total = segs.reduce((a, s) => a + s.value, 0);

  if (total <= 0) {
    pie.style.background = 'conic-gradient(#334155 0 100%)';
    return;
  }

  let acc = 0;
  const parts = segs.map((s) => {
    const start = acc;
    const pct = (s.value / total) * 100;
    acc += pct;
    return `${s.color} ${start}% ${acc}%`;
  });

  pie.style.background = `conic-gradient(${parts.join(',')})`;
}

function wireTabs() {
  const tabs = Array.from(document.querySelectorAll('.tab'));
  tabs.forEach((t) => {
    t.onclick = () => {
      tabs.forEach((x) => x.classList.remove('active'));
      t.classList.add('active');
      const id = t.getAttribute('data-tab');
      for (const p of document.querySelectorAll('.panel')) p.classList.add('hidden');
      el(`panel-${id}`).classList.remove('hidden');
    };
  });
}

async function loadLines() {
  const data = await api('/ops/lines');
  const rows = data.rows || [];

  const lineSelect = el('lineSelect');
  lineSelect.innerHTML = '';
  for (const l of rows) {
    const opt = document.createElement('option');
    opt.value = l.id;
    opt.textContent = `${l.oznaka} — ${l.naziv}`;
    lineSelect.appendChild(opt);
  }

  const cLine = el('cLine');
  cLine.innerHTML = '';
  const all = document.createElement('option');
  all.value = '';
  all.textContent = 'Sve';
  cLine.appendChild(all);
  for (const l of rows) {
    const opt = document.createElement('option');
    opt.value = l.id;
    opt.textContent = `${l.oznaka} — ${l.naziv}`;
    cLine.appendChild(opt);
  }
}

async function loadTimetable() {
  const lineId = Number(el('lineSelect').value);
  if (!lineId) return;

  const data = await api(`/ops/timetable?linija_id=${lineId}`);

  const body = el('timetableBody');
  body.innerHTML = '';
  for (const r of data.rows || []) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${r.vrijeme_polaska}</td>
      <td>${r.tip_vozila}</td>
      <td>${r.kalendar_naziv}</td>
    `;
    body.appendChild(tr);
  }

  const sbody = el('stopsBody');
  sbody.innerHTML = '';
  for (const s of data.stops || []) {
    const tr = document.createElement('tr');
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

  if (el('cStatus').value) params.set('status', el('cStatus').value);
  if (el('cCategory').value) params.set('kategorija', el('cCategory').value);
  if (el('cLine').value) params.set('linija_id', el('cLine').value);

  const data = await api(`/ops/complaints?${params.toString()}`);
  const body = el('complaintsBody');

  body.innerHTML = '';

  for (const r of data.rows || []) {
    const line = r.linija_oznaka || '—';
    const email = r.korisnik_email || '—';

    const tr = document.createElement('tr');

    tr.innerHTML = `
      <td>${fmt(r.datum_prituzbe)}</td>

      <td>
        <select class="input input--small" data-status data-id="${r.id}">
          <option value="Novo" ${r.status_rjesavanja === 'Novo' ? 'selected' : ''}>Novo</option>
          <option value="U obradi" ${r.status_rjesavanja === 'U obradi' ? 'selected' : ''}>U obradi</option>
          <option value="Riješeno" ${r.status_rjesavanja === 'Riješeno' ? 'selected' : ''}>Riješeno</option>
          <option value="Odbačeno" ${r.status_rjesavanja === 'Odbačeno' ? 'selected' : ''}>Odbačeno</option>
        </select>
      </td>

      <td>${r.kategorija_prituzbe || ''}</td>
      <td>${line}</td>
      <td>${email}</td>

      <td title="${(r.tekst_prituzbe || '').replaceAll('"', '&quot;')}">
        ${truncate(r.tekst_prituzbe, 120)}
      </td>
    `;

    body.appendChild(tr);
  }

  body.querySelectorAll('[data-status]').forEach((select) => {
    select.onchange = async () => {
      clearError();

      const id = select.getAttribute('data-id');
      const status = select.value;

      try {
        await api(`/ops/complaints/${id}`, {
          method: 'PATCH',
          body: JSON.stringify({ status_rjesavanja: status }),
        });

        await loadDashboard();
      } catch (e) {
        showError(e.message);
      }
    };
  });
}

function openComplaintModal(id) {
  const modal = el('complaintModal');
  const r = COMPLAINTS_BY_ID.get(String(id));
  if (!modal || !r) return;

  OPEN_COMPLAINT_ID = String(id);

  el('cmId').value = r.id ?? '';
  el('cmDate').value = fmt(r.datum_prituzbe);
  el('cmStatus').value = r.status_rjesavanja || 'Novo';
  el('cmCategory').value = r.kategorija_prituzbe || '';

  const line = r.linija_oznaka ? `${r.linija_oznaka} — ${r.linija_naziv}` : '—';
  el('cmLine').value = line;

  el('cmUser').value = r.korisnik_ime || '—';
  el('cmEmail').value = r.korisnik_email || '—';
  el('cmText').value = r.tekst_prituzbe || '';

  modal.showModal();
}

async function saveOpenComplaintStatus() {
  if (!OPEN_COMPLAINT_ID) return;
  clearError();
  const id = OPEN_COMPLAINT_ID;
  const status = el('cmStatus')?.value || 'Novo';
  try {
    await api(`/ops/complaints/${id}`, { method: 'PATCH', body: JSON.stringify({ status_rjesavanja: status }) });
    el('complaintModal')?.close();
    OPEN_COMPLAINT_ID = null;
    await loadComplaints();
    await loadDashboard();
  } catch (e) {
    showError(e.message);
  }
}

async function loadMaintenance() {
  const params = new URLSearchParams();
  if (el('mType').value) params.set('vrsta', el('mType').value);
  if (el('mFrom').value) params.set('from', el('mFrom').value);
  if (el('mTo').value) params.set('to', el('mTo').value);

  const data = await api(`/ops/maintenance?${params.toString()}`);
  const body = el('maintenanceBody');
  body.innerHTML = '';

  for (const r of data.rows || []) {
    const vehicle = `${r.tip_vozila} • ${r.vrsta_goriva} • ${r.kapacitet_putnika} putnika`;
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${r.datum_servisa}</td>
      <td>${vehicle}</td>
      <td>${r.vrsta_servisa}</td>
      <td>${r.trosak_servisa}</td>
      <td>${r.mehanicar || ''}</td>
      <td title="${String(r.opis_radova || '').replaceAll('"', '&quot;')}">${truncate(r.opis_radova, 90)}</td>
    `;
    body.appendChild(tr);
  }
}

async function loadMaintenanceLookups() {
  const [vehicles, mechanics] = await Promise.all([api('/ops/vehicles'), api('/ops/mechanics')]);

  const vSel = el('amVehicle');
  vSel.innerHTML = '';
  for (const v of vehicles.rows || []) {
    const opt = document.createElement('option');
    opt.value = v.id;
    opt.textContent = `${v.tip_vozila} • ${v.vrsta_goriva} • ${v.kapacitet_putnika} putnika ${
      v.u_prometu ? '(u prometu)' : '(van prometa)'
    }`;
    vSel.appendChild(opt);
  }

  const mSel = el('amMechanic');
  mSel.innerHTML = '';
  for (const m of mechanics.rows || []) {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = m.label;
    mSel.appendChild(opt);
  }
}

async function saveMaintenance() {
  clearError();
  const payload = {
    vozilo_id: el('amVehicle').value,
    zaposlenik_id: el('amMechanic').value,
    datum_servisa: el('amDate').value,
    vrsta_servisa: el('amType').value,
    trosak_servisa: el('amCost').value,
    opis_radova: el('amDesc').value,
  };

  if (!payload.datum_servisa) {
    showError('Odaberi datum servisa.');
    return;
  }
  if (payload.trosak_servisa === '' || payload.trosak_servisa == null) {
    showError('Upiši trošak servisa.');
    return;
  }

  await api('/ops/maintenance', { method: 'POST', body: JSON.stringify(payload) });
}

async function loadFines() {
  const params = new URLSearchParams();
  if (el('fStatus').value) params.set('status', el('fStatus').value);
  if (el('fFrom').value) params.set('from', el('fFrom').value);
  if (el('fTo').value) params.set('to', el('fTo').value);

  const data = await api(`/ops/fines?${params.toString()}`);
  const body = el('finesBody');
  body.innerHTML = '';

  for (const r of data.rows || []) {
    const user = `${r.korisnik_ime}${r.korisnik_email ? ' (' + r.korisnik_email + ')' : ''}`;
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${fmt(r.datum_prekrsaja)}</td>
      <td>${user}</td>
      <td>${r.iznos_kazne}</td>
      <td>${badgeFine(r.status_placanja)}</td>
      <td title="${String(r.napomena || '').replaceAll('"', '&quot;')}">${truncate(r.napomena, 70)}</td>
      <td>
        <select class="input input--small" data-fine-status data-id="${r.id}">
          <option value="Neplaćeno" ${r.status_placanja === 'Neplaćeno' ? 'selected' : ''}>Neplaćeno</option>
          <option value="U postupku" ${r.status_placanja === 'U postupku' ? 'selected' : ''}>U postupku</option>
          <option value="Plaćeno" ${r.status_placanja === 'Plaćeno' ? 'selected' : ''}>Plaćeno</option>
        </select>
        <button class="btnLink" data-fine-save data-id="${r.id}" type="button">Spremi</button>
      </td>
    `;
    body.appendChild(tr);
  }

  body.querySelectorAll('[data-fine-save]').forEach((btn) => {
    btn.onclick = async () => {
      clearError();
      const id = btn.getAttribute('data-id');
      const sel = body.querySelector(`[data-fine-status][data-id="${id}"]`);
      const status = sel ? sel.value : '';
      try {
        await api(`/ops/fines/${id}`, { method: 'PATCH', body: JSON.stringify({ status_placanja: status }) });
        await loadFines();
        await loadDashboard();
      } catch (e) {
        showError(e.message);
      }
    };
  });
}

function wireAutoReload() {
  el('lineSelect').addEventListener('change', async () => {
    clearError();
    try {
      await loadTimetable();
    } catch (e) {
      showError(e.message);
    }
  });

  ['cStatus', 'cCategory', 'cLine'].forEach((id) => {
    el(id).addEventListener('change', async () => {
      clearError();
      try {
        await loadComplaints();
        await loadDashboard();
      } catch (e) {
        showError(e.message);
      }
    });
  });

  ['mType', 'mFrom', 'mTo'].forEach((id) => {
    el(id).addEventListener('change', async () => {
      clearError();
      try {
        await loadMaintenance();
      } catch (e) {
        showError(e.message);
      }
    });
  });

  ['fStatus', 'fFrom', 'fTo'].forEach((id) => {
    el(id).addEventListener('change', async () => {
      clearError();
      try {
        await loadFines();
        await loadDashboard();
      } catch (e) {
        showError(e.message);
      }
    });
  });
}

async function init() {
  wireTabs();

  el('refreshAll').onclick = async () => {
    clearError();
    try {
      await Promise.all([loadDashboard(), loadComplaints(), loadMaintenance(), loadFines()]);
      await loadTimetable();
    } catch (e) {
      showError(e.message);
    }
  };

  el('loadTimetable').onclick = async () => {
    clearError();
    try {
      await loadTimetable();
    } catch (e) {
      showError(e.message);
    }
  };

  el('loadComplaints').onclick = async () => {
    clearError();
    try {
      await loadComplaints();
      await loadDashboard();
    } catch (e) {
      showError(e.message);
    }
  };

  el('loadMaintenance').onclick = async () => {
    clearError();
    try {
      await loadMaintenance();
    } catch (e) {
      showError(e.message);
    }
  };

  el('loadFines').onclick = async () => {
    clearError();
    try {
      await loadFines();
      await loadDashboard();
    } catch (e) {
      showError(e.message);
    }
  };

  const cModal = el('complaintModal');
  const cSave = el('cmSave');
  if (cSave) cSave.onclick = saveOpenComplaintStatus;
  if (cModal) {
    cModal.addEventListener('close', () => {
      OPEN_COMPLAINT_ID = null;
    });
  }

  const modal = el('maintenanceModal');
  el('openAddMaintenance').onclick = async () => {
    clearError();
    try {
      await loadMaintenanceLookups();
      el('amDate').value = new Date().toISOString().slice(0, 10);
      el('amCost').value = '';
      el('amDesc').value = '';
      modal.showModal();
    } catch (e) {
      showError(e.message);
    }
  };

  el('saveMaintenance').onclick = async () => {
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
    wireAutoReload();

    await loadDashboard();

    if (el('lineSelect').value) await loadTimetable();

    await Promise.all([loadComplaints(), loadMaintenance(), loadFines()]);
  } catch (e) {
    showError(e.message);
  }
}

init();
