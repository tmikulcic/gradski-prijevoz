import express from "express";
import { pool } from "./db.js";
import { LINije_STANICE } from "./config.tables.js";

export const linijeStaniceRouter = express.Router();

linijeStaniceRouter.get("/", async (req, res) => {
  const [rows] = await pool.query(
    `SELECT ${LINije_STANICE.columns.join(", ")}
     FROM ${LINije_STANICE.table}
     ORDER BY linija_id ASC, redoslijed ASC`
  );
  res.json({ rows });
});

linijeStaniceRouter.post("/", async (req, res) => {
  const { linija_id, stanica_id, redoslijed } = req.body || {};
  if (linija_id == null || stanica_id == null || redoslijed == null) {
    return res.status(400).json({ error: "linija_id, stanica_id, redoslijed su obavezni." });
  }

  await pool.query(
    `INSERT INTO ${LINije_STANICE.table} (linija_id, stanica_id, redoslijed) VALUES (?, ?, ?)`,
    [linija_id, stanica_id, redoslijed]
  );

  res.status(201).json({ ok: true });
});

linijeStaniceRouter.put("/", async (req, res) => {
  const { linija_id, stanica_id, redoslijed } = req.body || {};
  if (linija_id == null || stanica_id == null || redoslijed == null) {
    return res.status(400).json({ error: "linija_id, stanica_id, redoslijed su obavezni." });
  }

  const [result] = await pool.query(
    `UPDATE ${LINije_STANICE.table} SET redoslijed = ? WHERE linija_id = ? AND stanica_id = ?`,
    [redoslijed, linija_id, stanica_id]
  );

  res.json({ affectedRows: result.affectedRows });
});

linijeStaniceRouter.delete("/", async (req, res) => {
  const { linija_id, stanica_id } = req.body || {};
  if (linija_id == null || stanica_id == null) {
    return res.status(400).json({ error: "linija_id i stanica_id su obavezni." });
  }

  const [result] = await pool.query(
    `DELETE FROM ${LINije_STANICE.table} WHERE linija_id = ? AND stanica_id = ?`,
    [linija_id, stanica_id]
  );

  res.json({ affectedRows: result.affectedRows });
});
