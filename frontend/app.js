const API_BASE = "http://localhost:3000/api";

const el = (id) => document.getElementById(id);

const state = {
  tables: [],
  activeTable: null,
  page: 1,
  pageSize: 25,
  search: "",
  rows: [],
  columns: [],
  total: 0,
  editingId: null
};

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
  el("error").classList.add("hidden");
  el("error").textContent = "";
}

function renderNav() {
  const nav = el("nav");
  nav.innerHTML = "";

  for (const t of state.tables) {
    const item = document.createElement("div");
    item.className = `navItem ${state.activeTable === t ? "active" : ""}`;
    item.innerHTML = `<span>${t}</span><span class="muted">CRUD</span>`;
    item.onclick = () => selectTable(t);
    nav.appendChild(item);
  }

  const special = document.createElement("div");
  special.className = `navItem ${state.activeTable === "linije_stanice" ? "active" : ""}`;
  special.innerHTML = `<span>linije_stanice</span><span class="muted">PK x2</span>`;
  special.onclick = () => selectTable("linije_stanice");
  nav.appendChild(special);
}

async function loadTables() {
  const data = await api("/tables");
  state.tables = data.tables;
  renderNav();
}

async function selectTable(t) {
  state.activeTable = t;
  state.page = 1;
  state.search = "";
  el("search").value = "";
  renderNav();
  await loadRows();
}

function renderTable() {
  el("title").textContent = state.activeTable || "Odaberi tablicu";
  el("meta").textContent = state.activeTable ? `pageSize: ${state.pageSize}` : "";
  el("new").disabled = !state.activeTable;

  const thead = el("thead");
  const tbody = el("tbody");

  thead.innerHTML = "";
  tbody.innerHTML = "";

  if (!state.activeTable) return;

  if (state.activeTable === "linije_stanice") {
    state.columns = ["linija_id", "stanica_id", "redoslijed"];
  }

  const trh = document.createElement("tr");
  for (const c of state.columns) {
    const th = document.createElement("th");
    th.textContent = c;
    trh.appendChild(th);
  }
  const thA = document.createElement("th");
  thA.textContent = "Akcije";
  trh.appendChild(thA);
  thead.appendChild(trh);

  for (const row of state.rows) {
    const tr = document.createElement("tr");
    for (const c of state.columns) {
      const td = document.createElement("td");
      td.textContent = row[c] ?? "";
      tr.appendChild(td);
    }

    const actions = document.createElement("td");
    const btn = document.createElement("span");
    btn.className = "rowBtn";
    btn.textContent = "Edit";
    btn.onclick = () => openEdit(row);
    actions.appendChild(btn);
    tr.appendChild(actions);

    tbody.appendChild(tr);
  }

  const totalPages = Math.max(1, Math.ceil(state.total / state.pageSize));
  el("pagerInfo").textContent = `Page ${state.page} / ${totalPages} — total: ${state.total}`;
  el("prev").disabled = state.page <= 1;
  el("next").disabled = state.page >= totalPages;
}

function buildFields(columns, row) {
  const fields = el("fields");
  fields.innerHTML = "";

  for (const c of columns) {
    const wrap = document.createElement("div");
    wrap.className = "field";

    const label = document.createElement("label");
    label.textContent = c;

    const input = document.createElement("input");
    input.name = c;
    input.value = row?.[c] ?? "";

    wrap.appendChild(label);
    wrap.appendChild(input);
    fields.appendChild(wrap);
  }
}

function openEdit(row) {
  state.editingId = row?.id ?? null;

  const modal = el("modal");
  const del = el("delete");
  del.classList.toggle("hidden", !row);

  if (state.activeTable === "linije_stanice") {
    el("modalTitle").textContent = "Edit linije_stanice";
    buildFields(["linija_id", "stanica_id", "redoslijed"], row);

    del.onclick = async () => {
      await api("/linije-stanice", {
        method: "DELETE",
        body: JSON.stringify({ linija_id: row.linija_id, stanica_id: row.stanica_id })
      });
      modal.close();
      await loadRows();
    };
  } else {
    el("modalTitle").textContent = row ? `Edit ${state.activeTable} #${row.id}` : `Novi ${state.activeTable}`;
    const cols = state.columns.filter((c) => c !== "id");
    buildFields(cols, row);

    del.onclick = async () => {
      await api(`/crud/${state.activeTable}/${row.id}`, { method: "DELETE" });
      modal.close();
      await loadRows();
    };
  }

  modal.showModal();
}

async function saveForm() {
  const form = el("form");
  const fd = new FormData(form);
  const payload = {};
  for (const [k, v] of fd.entries()) payload[k] = v;

  if (state.activeTable === "linije_stanice") {
    // jednostavno: korisnik mijenja redoslijed za postojeći par (linija_id, stanica_id)
    await api("/linije-stanice", { method: "PUT", body: JSON.stringify(payload) });
  } else {
    if (state.editingId) {
      await api(`/crud/${state.activeTable}/${state.editingId}`, { method: "PUT", body: JSON.stringify(payload) });
    } else {
      await api(`/crud/${state.activeTable}`, { method: "POST", body: JSON.stringify(payload) });
    }
  }

  el("modal").close();
  await loadRows();
}

async function loadRows() {
  clearError();

  if (!state.activeTable) return;

  try {
    if (state.activeTable === "linije_stanice") {
      const data = await api("/linije-stanice");
      state.rows = data.rows;
      state.total = data.rows.length;
      state.columns = ["linija_id", "stanica_id", "redoslijed"];
    } else {
      const data = await api(`/crud/${state.activeTable}?page=${state.page}&pageSize=${state.pageSize}&search=${encodeURIComponent(state.search)}`);
      state.rows = data.rows;
      state.total = data.total;
      state.columns = (data.rows[0] && Object.keys(data.rows[0])) || state.columns || [];
    }

    renderTable();
  } catch (e) {
    showError(e.message);
  }
}

function wire() {
  el("refresh").onclick = async () => {
    await loadTables();
    if (state.activeTable) await loadRows();
  };

  el("search").addEventListener("input", async (e) => {
    state.search = e.target.value.trim();
    state.page = 1;
    await loadRows();
  });

  el("prev").onclick = async () => {
    state.page = Math.max(1, state.page - 1);
    await loadRows();
  };

  el("next").onclick = async () => {
    state.page = state.page + 1;
    await loadRows();
  };

  el("new").onclick = () => {
    state.editingId = null;
    const del = el("delete");
    del.classList.add("hidden");

    if (state.activeTable === "linije_stanice") {
      el("modalTitle").textContent = "Novi linije_stanice";
      buildFields(["linija_id", "stanica_id", "redoslijed"], {});
    } else {
      el("modalTitle").textContent = `Novi ${state.activeTable}`;
      buildFields(state.columns.filter((c) => c !== "id"), {});
    }

    el("modal").showModal();
  };

  el("save").onclick = async (e) => {
    e.preventDefault();
    await saveForm();
  };
}

(async function init() {
  wire();
  await loadTables();
})();
