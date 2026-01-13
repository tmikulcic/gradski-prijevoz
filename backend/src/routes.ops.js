import express from 'express';
import { pool } from './db.js';

export const opsRouter = express.Router();

const ALLOWED_COMPLAINT_STATUS = ['Novo', 'U obradi', 'Riješeno', 'Odbačeno'];
const ALLOWED_FINE_STATUS = ['Plaćeno', 'Neplaćeno', 'U postupku'];
const ALLOWED_SERVICE_TYPE = ['Redovni', 'Izvanredni', 'Tehnički pregled', 'Popravak kvar'];

function toInt(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

opsRouter.get('/dashboard', async (req, res) => {
  try {
    // KPI: vozila u prometu
    const [[vozila]] = await pool.query(
      `SELECT
        SUM(CASE WHEN u_prometu = 1 THEN 1 ELSE 0 END) AS u_prometu,
        SUM(CASE WHEN u_prometu = 0 THEN 1 ELSE 0 END) AS van_prometa,
        COUNT(*) AS ukupno
      FROM vozila`
    );

    // 1) Vozila po gorivu
    const [vozilaPoGorivu] = await pool.query(
      `SELECT vrsta_goriva AS label, COUNT(*) AS value
       FROM vozila
       GROUP BY vrsta_goriva
       ORDER BY value DESC, label ASC`
    );

    // 2) Pritužbe po statusu
    const [prituzbePoStatusu] = await pool.query(
      `SELECT status_rjesavanja AS label, COUNT(*) AS value
       FROM prituzbe
       GROUP BY status_rjesavanja
       ORDER BY value DESC, label ASC`
    );

    // 3) Pritužbe po kategoriji
    const [prituzbePoKategoriji] = await pool.query(
      `SELECT kategorija_prituzbe AS label, COUNT(*) AS value
       FROM prituzbe
       GROUP BY kategorija_prituzbe
       ORDER BY value DESC, label ASC`
    );

    // 4) Prekršaji po statusu
    const [prekrsajiPoStatusu] = await pool.query(
      `SELECT status_placanja AS label, COUNT(*) AS value
       FROM prekrsaji
       GROUP BY status_placanja
       ORDER BY value DESC, label ASC`
    );

    // 5) Servisi po vrsti
    const [servisiPoVrsti] = await pool.query(
      `SELECT vrsta_servisa AS label, COUNT(*) AS value
       FROM odrzavanje_vozila
       GROUP BY vrsta_servisa
       ORDER BY value DESC, label ASC`
    );

    // 6) Zaposlenici po ulozi
    const [zaposleniciPoUlozi] = await pool.query(
      `SELECT naziv_uloge AS label, COUNT(*) AS value
       FROM zaposlenik
       GROUP BY naziv_uloge
       ORDER BY value DESC, label ASC`
    );

    // 7) Prodane karte po tipu
    const [kartePoTipu] = await pool.query(
      `SELECT tk.tip_naziv AS label, COUNT(*) AS value
       FROM karta k
       JOIN tip_karte tk ON tk.id = k.tip_karte_id
       GROUP BY tk.id, tk.tip_naziv
       ORDER BY value DESC, tk.tip_naziv ASC`
    );

    res.json({
      vozila,
      charts: {
        vozila_po_gorivu: vozilaPoGorivu,
        prituzbe_po_statusu: prituzbePoStatusu,
        prituzbe_po_kategoriji: prituzbePoKategoriji,
        prekrsaji_po_statusu: prekrsajiPoStatusu,
        servisi_po_vrsti: servisiPoVrsti,
        zaposlenici_po_ulozi: zaposleniciPoUlozi,
        prodane_karte_po_tipu: kartePoTipu,
      },
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message || 'Dashboard error' });
  }
});

opsRouter.get('/lines', async (req, res) => {
  const [rows] = await pool.query(
    `SELECT id, oznaka, naziv, tip_linije
     FROM linije
     ORDER BY CAST(oznaka AS UNSIGNED), oznaka`
  );
  res.json({ rows });
});

opsRouter.get('/vehicles', async (req, res) => {
  const [rows] = await pool.query(
    `SELECT id, tip_vozila, u_prometu, vrsta_goriva, kapacitet_putnika
     FROM vozila
     ORDER BY tip_vozila, id`
  );
  res.json({ rows });
});

opsRouter.get('/mechanics', async (req, res) => {
  const [rows] = await pool.query(
    `SELECT id, CONCAT(ime, ' ', prezime) AS label
     FROM zaposlenik
     WHERE naziv_uloge = 'Mehaničar'
     ORDER BY prezime, ime`
  );
  res.json({ rows });
});

opsRouter.get('/timetable', async (req, res) => {
  const linijaId = toInt(req.query.linija_id);
  if (!linijaId || linijaId <= 0) return res.status(400).json({ error: 'linija_id je obavezan.' });

  const [[line]] = await pool.query(
    `SELECT id, oznaka, naziv, tip_linije
     FROM linije
     WHERE id = ?
     LIMIT 1`,
    [linijaId]
  );

  const [rows] = await pool.query(
    `SELECT
       vr.id,
       vr.vrijeme_polaska,
       v.tip_vozila,
       k.kalendar_naziv
     FROM vozni_red vr
     JOIN vozila v ON v.id = vr.vozilo_id
     JOIN kalendari k ON k.id = vr.kalendar_id
     WHERE vr.linija_id = ?
     ORDER BY vr.vrijeme_polaska ASC`,
    [linijaId]
  );

  const [stops] = await pool.query(
    `SELECT
       ls.redoslijed,
       s.naziv AS stanica,
       z.zona_kod
     FROM linije_stanice ls
     JOIN stanice s ON s.id = ls.stanica_id
     JOIN zone z ON z.id = s.zona_id
     WHERE ls.linija_id = ?
     ORDER BY ls.redoslijed ASC`,
    [linijaId]
  );

  res.json({ line: line || null, rows, stops });
});

opsRouter.get('/complaints', async (req, res) => {
  const status = req.query.status ? String(req.query.status) : '';
  const kategorija = req.query.kategorija ? String(req.query.kategorija) : '';
  const linijaId = req.query.linija_id ? toInt(req.query.linija_id) : null;

  const where = [];
  const params = [];

  if (status) {
    where.push('pr.status_rjesavanja = ?');
    params.push(status);
  }
  if (kategorija) {
    where.push('pr.kategorija_prituzbe = ?');
    params.push(kategorija);
  }
  if (linijaId) {
    where.push('pr.linija_id = ?');
    params.push(linijaId);
  }

  const sqlWhere = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const [rows] = await pool.query(
    `SELECT
       pr.id,
       pr.datum_prituzbe,
       pr.kategorija_prituzbe,
       pr.status_rjesavanja,
       pr.tekst_prituzbe,
       CONCAT(k.ime, ' ', k.prezime) AS korisnik_ime,
       k.email AS korisnik_email,
       l.oznaka AS linija_oznaka,
       l.naziv AS linija_naziv
     FROM prituzbe pr
     JOIN korisnici k ON k.id = pr.korisnik_id
     LEFT JOIN linije l ON l.id = pr.linija_id
     ${sqlWhere}
     ORDER BY pr.datum_prituzbe DESC
     LIMIT 500`,
    params
  );

  res.json({ rows });
});

opsRouter.patch('/complaints/:id', async (req, res) => {
  const id = toInt(req.params.id);
  const status = req.body?.status_rjesavanja ? String(req.body.status_rjesavanja) : '';

  if (!id) return res.status(400).json({ error: 'id je obavezan.' });
  if (!ALLOWED_COMPLAINT_STATUS.includes(status)) {
    return res.status(400).json({ error: 'Neispravan status_rjesavanja.' });
  }

  const [result] = await pool.query(
    `UPDATE prituzbe
     SET status_rjesavanja = ?
     WHERE id = ?`,
    [status, id]
  );

  res.json({ ok: true, affectedRows: result.affectedRows });
});

opsRouter.get('/fines', async (req, res) => {
  const status = req.query.status ? String(req.query.status) : '';
  const from = req.query.from ? String(req.query.from) : '';
  const to = req.query.to ? String(req.query.to) : '';

  const where = [];
  const params = [];

  if (status) {
    where.push('p.status_placanja = ?');
    params.push(status);
  }
  if (from) {
    where.push('p.datum_prekrsaja >= ?');
    params.push(from);
  }
  if (to) {
    where.push('p.datum_prekrsaja <= ?');
    params.push(to);
  }

  const sqlWhere = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const [rows] = await pool.query(
    `SELECT
       p.id,
       p.datum_prekrsaja,
       p.iznos_kazne,
       p.status_placanja,
       p.napomena,
       CONCAT(k.ime, ' ', k.prezime) AS korisnik_ime,
       k.email AS korisnik_email
     FROM prekrsaji p
     JOIN korisnici k ON k.id = p.korisnik_id
     ${sqlWhere}
     ORDER BY p.datum_prekrsaja DESC
     LIMIT 500`,
    params
  );

  res.json({ rows });
});

opsRouter.patch('/fines/:id', async (req, res) => {
  const id = toInt(req.params.id);
  const status = req.body?.status_placanja ? String(req.body.status_placanja) : '';

  if (!id) return res.status(400).json({ error: 'id je obavezan.' });
  if (!ALLOWED_FINE_STATUS.includes(status)) return res.status(400).json({ error: 'Neispravan status_placanja.' });

  const [result] = await pool.query(
    `UPDATE prekrsaji
     SET status_placanja = ?
     WHERE id = ?`,
    [status, id]
  );

  res.json({ ok: true, affectedRows: result.affectedRows });
});

opsRouter.get('/maintenance', async (req, res) => {
  const vrsta = req.query.vrsta ? String(req.query.vrsta) : '';
  const from = req.query.from ? String(req.query.from) : '';
  const to = req.query.to ? String(req.query.to) : '';

  const where = [];
  const params = [];

  if (vrsta) {
    where.push('o.vrsta_servisa = ?');
    params.push(vrsta);
  }
  if (from) {
    where.push('o.datum_servisa >= ?');
    params.push(from);
  }
  if (to) {
    where.push('o.datum_servisa <= ?');
    params.push(to);
  }

  const sqlWhere = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const [rows] = await pool.query(
    `SELECT
       o.id,
       o.datum_servisa,
       o.vrsta_servisa,
       o.trosak_servisa,
       o.opis_radova,
       v.tip_vozila,
       v.vrsta_goriva,
       v.kapacitet_putnika,
       CONCAT(z.ime, ' ', z.prezime) AS mehanicar
     FROM odrzavanje_vozila o
     JOIN vozila v ON v.id = o.vozilo_id
     JOIN zaposlenik z ON z.id = o.zaposlenik_id
     ${sqlWhere}
     ORDER BY o.datum_servisa DESC
     LIMIT 500`,
    params
  );

  res.json({ rows });
});

opsRouter.post('/maintenance', async (req, res) => {
  const voziloId = toInt(req.body?.vozilo_id);
  const zaposlenikId = toInt(req.body?.zaposlenik_id);
  const datum = req.body?.datum_servisa ? String(req.body.datum_servisa) : '';
  const vrsta = req.body?.vrsta_servisa ? String(req.body.vrsta_servisa) : '';
  const trosak = req.body?.trosak_servisa;

  const opis = req.body?.opis_radova ? String(req.body.opis_radova) : '';

  if (!voziloId) return res.status(400).json({ error: 'vozilo_id je obavezan.' });
  if (!zaposlenikId) return res.status(400).json({ error: 'zaposlenik_id je obavezan.' });
  if (!datum) return res.status(400).json({ error: 'datum_servisa je obavezan.' });
  if (!ALLOWED_SERVICE_TYPE.includes(vrsta)) return res.status(400).json({ error: 'Neispravan vrsta_servisa.' });

  const trosakNum = Number(trosak);
  if (!Number.isFinite(trosakNum) || trosakNum < 0)
    return res.status(400).json({ error: 'trosak_servisa mora biti broj >= 0.' });

  const [result] = await pool.query(
    `INSERT INTO odrzavanje_vozila (vozilo_id, zaposlenik_id, datum_servisa, vrsta_servisa, trosak_servisa, opis_radova)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [voziloId, zaposlenikId, datum, vrsta, trosakNum, opis || null]
  );

  res.status(201).json({ id: result.insertId });
});
