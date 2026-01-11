import express from "express";
import { pool } from "./db.js";
import { TABLES } from "./config.tables.js";

export const crudRouter = express.Router();

function mustBeTable(req, res, next) {
  const { table } = req.params;
  if (!TABLES[table]) {
    return res.status(404).json({ error: "Nepoznata tablica." });
  }
  req.tableConfig = TABLES[table];
  next();
}

function pickAllowed(body, allowed) {
  const out = {};
  for (const key of allowed) {
    if (Object.prototype.hasOwnProperty.call(body, key)) out[key] = body[key];
  }
  return out;
}

function normalizeValue(col, val) {
  if (val == null) return val;
  if (typeof val !== "string") return val;

  const v = val.trim();
  if (!v) return v;

  // ISO -> DATE (YYYY-MM-DD)
  if (/^\d{4}-\d{2}-\d{2}T/.test(v)) {
    // heuristika po nazivu stupca:
    // ako je "datum_*" i nije "datum_*" za datetime? (mi ćemo: ako kolona ima "datum" i nema "kupnje"/"prekrsaja"/"prituzbe" -> DATE)
    // ali najjednostavnije: ako kolona izgleda kao DATE (npr datum_zaposlenja, datum_servisa, datum_rodenja)
    const likelyDateOnly =
      col === "datum_zaposlenja" ||
      col === "datum_servisa" ||
      col === "datum_rodenja";

    if (likelyDateOnly) return v.slice(0, 10); // YYYY-MM-DD

    // za DATETIME: "YYYY-MM-DD HH:MM:SS"
    const base = v.replace("T", " ").replace("Z", "");
    // makni milisekunde ako postoje
    return base.replace(/\.\d{3}$/, "");
  }

  return v;
}

function normalizePayload(cfg, data) {
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (!cfg.columns.includes(k)) continue;
    out[k] = normalizeValue(k, v);
  }
  return out;
}

crudRouter.get("/:table", mustBeTable, async (req, res) => {
  const { table } = req.params;
  const cfg = req.tableConfig;

  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(200, Math.max(1, Number(req.query.pageSize || 25)));
  const offset = (page - 1) * pageSize;

  const search = String(req.query.search || "").trim();
  const filtersRaw = req.query.filters ? String(req.query.filters) : "";
  let filters = {};
  if (filtersRaw) {
    try {
      filters = JSON.parse(filtersRaw);
    } catch {
      filters = {};
    }
  }

  const where = [];
  const params = [];

  if (search && cfg.searchColumns?.length) {
    const likeParts = cfg.searchColumns.map((c) => `CAST(${c} AS CHAR) LIKE ?`);
    where.push(`(${likeParts.join(" OR ")})`);
    for (let i = 0; i < cfg.searchColumns.length; i++) params.push(`%${search}%`);
  }

  for (const [key, val] of Object.entries(filters)) {
    if (!cfg.columns.includes(key)) continue;
    where.push(`${key} = ?`);
    params.push(val);
  }

  const whereSql = where.length ? `WHERE ${where.join(" AND ")}` : "";

  const [countRows] = await pool.query(
    `SELECT COUNT(*) as total FROM ${table} ${whereSql}`,
    params
  );

  const [rows] = await pool.query(
    `SELECT ${cfg.columns.join(", ")} FROM ${table} ${whereSql} ORDER BY ${cfg.pk[0]} DESC LIMIT ? OFFSET ?`,
    [...params, pageSize, offset]
  );

  res.json({
    page,
    pageSize,
    total: Number(countRows?.[0]?.total || 0),
    rows
  });
});

crudRouter.get("/:table/:id", mustBeTable, async (req, res) => {
  const { table, id } = req.params;
  const cfg = req.tableConfig;

  const [rows] = await pool.query(
    `SELECT ${cfg.columns.join(", ")} FROM ${table} WHERE ${cfg.pk[0]} = ? LIMIT 1`,
    [id]
  );

  if (!rows.length) return res.status(404).json({ error: "Nije pronađeno." });
  res.json(rows[0]);
});

crudRouter.post("/:table", mustBeTable, async (req, res) => {
  const { table } = req.params;
  const cfg = req.tableConfig;

  const raw = pickAllowed(req.body || {}, cfg.columns.filter((c) => c !== "id"));
  const data = normalizePayload(cfg, raw);

  const cols = Object.keys(data);
  if (!cols.length) return res.status(400).json({ error: "Nema podataka za insert." });

  const placeholders = cols.map(() => "?").join(", ");
  const values = cols.map((c) => data[c]);

  const [result] = await pool.query(
    `INSERT INTO ${table} (${cols.join(", ")}) VALUES (${placeholders})`,
    values
  );

  res.status(201).json({ id: result.insertId });
});

crudRouter.put("/:table/:id", mustBeTable, async (req, res) => {
  const { table, id } = req.params;
  const cfg = req.tableConfig;

  const raw = pickAllowed(req.body || {}, cfg.columns.filter((c) => c !== "id"));
  const data = normalizePayload(cfg, raw);

  const cols = Object.keys(data);
  if (!cols.length) return res.status(400).json({ error: "Nema podataka za update." });

  const setSql = cols.map((c) => `${c} = ?`).join(", ");
  const values = cols.map((c) => data[c]);

  const [result] = await pool.query(
    `UPDATE ${table} SET ${setSql} WHERE ${cfg.pk[0]} = ?`,
    [...values, id]
  );

  res.json({ affectedRows: result.affectedRows });
});

crudRouter.delete("/:table/:id", mustBeTable, async (req, res) => {
  const { table, id } = req.params;
  const cfg = req.tableConfig;

  const [result] = await pool.query(
    `DELETE FROM ${table} WHERE ${cfg.pk[0]} = ?`,
    [id]
  );

  res.json({ affectedRows: result.affectedRows });
});