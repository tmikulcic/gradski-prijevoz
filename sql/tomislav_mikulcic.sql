USE gradski_prijevoz;

-- =========================================================
-- 1) 20 KOMPLEKSNIH SELECT UPITA
-- =========================================================

-- 1) Prihod i broj prodanih karata po tipu i mjesecu
SELECT
  tk.tip_kod,
  tk.tip_naziv,
  DATE_FORMAT(k.datum_kupnje, '%Y-%m') AS mjesec,
  COUNT(*) AS broj_karata,
  ROUND(SUM(k.placena_cijena), 2) AS prihod
FROM karta k
JOIN tip_karte tk ON tk.id = k.tip_karte_id
GROUP BY tk.tip_kod, tk.tip_naziv, DATE_FORMAT(k.datum_kupnje, '%Y-%m')
ORDER BY mjesec DESC, prihod DESC;

-- 2) Prosječna osnovna vs plaćena cijena po kategoriji putnika (popust)
SELECT
  kp.kategorija_kod,
  kp.kategorija_naziv,
  ROUND(AVG(tk.osnovna_cijena), 2) AS prosjecna_osnovna,
  ROUND(AVG(k.placena_cijena), 2) AS prosjecna_placena,
  ROUND(AVG(tk.osnovna_cijena - k.placena_cijena), 2) AS prosjecni_popust_iznos
FROM karta k
JOIN korisnici u ON u.id = k.korisnik_id
JOIN kategorija_putnik kp ON kp.id = u.kategorija_id
JOIN tip_karte tk ON tk.id = k.tip_karte_id
GROUP BY kp.kategorija_kod, kp.kategorija_naziv
ORDER BY prosjecni_popust_iznos DESC;

-- 3) Aktivna karta po korisniku (zadnja aktivna) - window
WITH ranked AS (
  SELECT
    k.*,
    ROW_NUMBER() OVER (PARTITION BY k.korisnik_id ORDER BY k.datum_kupnje DESC) AS rn
  FROM karta k
  WHERE NOW() BETWEEN k.datum_kupnje AND k.vrijedi_do
)
SELECT
  r.korisnik_id,
  u.ime, u.prezime, u.email,
  tk.tip_kod, tk.tip_naziv,
  r.datum_kupnje, r.vrijedi_do,
  r.placena_cijena
FROM ranked r
JOIN korisnici u ON u.id = r.korisnik_id
JOIN tip_karte tk ON tk.id = r.tip_karte_id
WHERE r.rn = 1
ORDER BY r.vrijedi_do ASC;

-- 4) Linije: broj stanica i broj različitih zona
SELECT
  l.oznaka,
  l.naziv,
  l.tip_linije,
  COUNT(ls.stanica_id) AS broj_stanica,
  COUNT(DISTINCT s.zona_id) AS broj_zona
FROM linije l
LEFT JOIN linije_stanice ls ON ls.linija_id = l.id
LEFT JOIN stanice s ON s.id = ls.stanica_id
GROUP BY l.id, l.oznaka, l.naziv, l.tip_linije
ORDER BY broj_stanica DESC, broj_zona DESC;

-- 5) Vozni red detaljno
SELECT
  l.oznaka AS linija,
  l.naziv AS naziv_linije,
  vr.vrijeme_polaska,
  v.tip_vozila,
  v.registarska_oznaka,
  z.zaposlenik_broj,
  CONCAT(z.ime, ' ', z.prezime) AS vozac,
  k.kalendar_naziv
FROM vozni_red vr
JOIN linije l ON l.id = vr.linija_id
JOIN vozila v ON v.id = vr.vozilo_id
JOIN zaposlenik z ON z.id = vr.vozac_id
JOIN kalendari k ON k.id = vr.kalendar_id
ORDER BY l.oznaka, vr.vrijeme_polaska;

-- 6) Sljedeći polazak po liniji i kalendaru (nakon trenutnog vremena)
SELECT
  l.oznaka,
  l.naziv,
  k.kalendar_naziv,
  MIN(vr.vrijeme_polaska) AS sljedeci_polazak
FROM linije l
JOIN vozni_red vr ON vr.linija_id = l.id
JOIN kalendari k ON k.id = vr.kalendar_id
WHERE vr.vrijeme_polaska > CURTIME()
GROUP BY l.id, l.oznaka, l.naziv, k.kalendar_naziv
ORDER BY sljedeci_polazak ASC;

-- 7) Vozila: ukupni trošak održavanja i zadnji servis
SELECT
  v.registarska_oznaka,
  v.tip_vozila,
  v.u_prometu,
  ROUND(IFNULL(SUM(o.trosak_servisa), 0), 2) AS trosak_ukupno,
  MAX(o.datum_servisa) AS zadnji_servis
FROM vozila v
LEFT JOIN odrzavanje_vozila o ON o.vozilo_id = v.id
GROUP BY v.id, v.registarska_oznaka, v.tip_vozila, v.u_prometu
ORDER BY trosak_ukupno DESC, zadnji_servis DESC;

-- 8) Mehaničari: broj servisa + prosjek troška
SELECT
  z.zaposlenik_broj,
  CONCAT(z.ime, ' ', z.prezime) AS mehanicar,
  COUNT(o.id) AS broj_servisa,
  ROUND(AVG(o.trosak_servisa), 2) AS prosjecni_trosak
FROM zaposlenik z
JOIN odrzavanje_vozila o ON o.zaposlenik_id = z.id
WHERE z.naziv_uloge = 'Mehaničar'
GROUP BY z.id, z.zaposlenik_broj, z.ime, z.prezime
ORDER BY broj_servisa DESC, prosjecni_trosak DESC;

-- 9) Ponavljani prekršitelji (više od 1 neplaćeni)
SELECT
  u.id AS korisnik_id,
  u.ime, u.prezime, u.email,
  COUNT(p.id) AS broj_neplacenih
FROM korisnici u
JOIN prekrsaji p ON p.korisnik_id = u.id
WHERE p.status_placanja = 'Neplaćeno'
GROUP BY u.id, u.ime, u.prezime, u.email
HAVING COUNT(p.id) > 1
ORDER BY broj_neplacenih DESC;

-- 10) Kazne po kategoriji putnika
SELECT
  kp.kategorija_kod,
  kp.kategorija_naziv,
  COUNT(p.id) AS broj_prekrsaja,
  ROUND(AVG(p.iznos_kazne), 2) AS prosjek,
  MAX(p.iznos_kazne) AS max_iznos
FROM prekrsaji p
JOIN korisnici u ON u.id = p.korisnik_id
JOIN kategorija_putnik kp ON kp.id = u.kategorija_id
GROUP BY kp.kategorija_kod, kp.kategorija_naziv
ORDER BY broj_prekrsaja DESC, prosjek DESC;

-- 11) Pritužbe po liniji i kategoriji + udio
WITH line_totals AS (
  SELECT linija_id, COUNT(*) AS total_cnt
  FROM prituzbe
  WHERE linija_id IS NOT NULL
  GROUP BY linija_id
)
SELECT
  l.oznaka,
  l.naziv,
  pr.kategorija_prituzbe,
  COUNT(*) AS broj,
  ROUND(COUNT(*) / lt.total_cnt * 100, 2) AS udio_postotak
FROM prituzbe pr
JOIN linije l ON l.id = pr.linija_id
JOIN line_totals lt ON lt.linija_id = pr.linija_id
GROUP BY l.id, l.oznaka, l.naziv, pr.kategorija_prituzbe, lt.total_cnt
ORDER BY l.oznaka, broj DESC;

-- 12) Stanice koje nisu na nijednoj liniji
SELECT
  s.id,
  s.naziv,
  z.zona_kod,
  z.zona_naziv
FROM stanice s
JOIN zone z ON z.id = s.zona_id
LEFT JOIN linije_stanice ls ON ls.stanica_id = s.id
WHERE ls.linija_id IS NULL
ORDER BY z.zona_kod, s.naziv;

-- 13) Linije bez voznog reda
SELECT
  l.id,
  l.oznaka,
  l.naziv,
  l.tip_linije
FROM linije l
LEFT JOIN vozni_red vr ON vr.linija_id = l.id
WHERE vr.id IS NULL
ORDER BY l.tip_linije, l.oznaka;

-- 14) Sekvenca stanica (prev/next) po liniji - window
SELECT
  l.oznaka AS linija,
  l.naziv AS naziv_linije,
  ls.redoslijed,
  s.naziv AS stanica,
  LAG(s.naziv) OVER (PARTITION BY l.id ORDER BY ls.redoslijed) AS prethodna_stanica,
  LEAD(s.naziv) OVER (PARTITION BY l.id ORDER BY ls.redoslijed) AS sljedeca_stanica
FROM linije l
JOIN linije_stanice ls ON ls.linija_id = l.id
JOIN stanice s ON s.id = ls.stanica_id
ORDER BY l.oznaka, ls.redoslijed;

-- 15) Kontrolori: broj kazni po mjesecu
SELECT
  z.zaposlenik_broj,
  CONCAT(z.ime,' ',z.prezime) AS kontrolor,
  DATE_FORMAT(p.datum_prekrsaja, '%Y-%m') AS mjesec,
  COUNT(*) AS broj_kazni,
  ROUND(SUM(p.iznos_kazne), 2) AS ukupno
FROM prekrsaji p
JOIN zaposlenik z ON z.id = p.zaposlenik_id
GROUP BY z.id, z.zaposlenik_broj, z.ime, z.prezime, DATE_FORMAT(p.datum_prekrsaja, '%Y-%m')
ORDER BY mjesec DESC, broj_kazni DESC;

-- 16) Aktivni korisnici bez ijedne kupljene karte
SELECT
  u.id, u.ime, u.prezime, u.email, u.status_racuna,
  kp.kategorija_kod
FROM korisnici u
JOIN kategorija_putnik kp ON kp.id = u.kategorija_id
LEFT JOIN karta k ON k.korisnik_id = u.id
WHERE u.status_racuna = 'Aktivan'
  AND k.id IS NULL
ORDER BY u.prezime, u.ime;

-- 17) Korisnici koji imaju i pritužbe i prekršaje
SELECT
  u.id,
  u.ime, u.prezime, u.email,
  COUNT(DISTINCT pr.id) AS broj_prituzbi,
  COUNT(DISTINCT pk.id) AS broj_prekrsaja
FROM korisnici u
LEFT JOIN prituzbe pr ON pr.korisnik_id = u.id
LEFT JOIN prekrsaji pk ON pk.korisnik_id = u.id
GROUP BY u.id, u.ime, u.prezime, u.email
HAVING COUNT(DISTINCT pr.id) > 0 AND COUNT(DISTINCT pk.id) > 0
ORDER BY broj_prekrsaja DESC, broj_prituzbi DESC;

-- 18) Pritužbe otvorene dulje od 10 dana
SELECT
  pr.id,
  pr.datum_prituzbe,
  pr.status_rjesavanja,
  pr.kategorija_prituzbe,
  u.ime, u.prezime, u.email,
  l.oznaka AS linija, l.naziv AS naziv_linije
FROM prituzbe pr
JOIN korisnici u ON u.id = pr.korisnik_id
LEFT JOIN linije l ON l.id = pr.linija_id
WHERE pr.status_rjesavanja IN ('Novo','U obradi')
  AND pr.datum_prituzbe < (NOW() - INTERVAL 10 DAY)
ORDER BY pr.datum_prituzbe ASC;

-- 19) Vozila van prometa + zadnji servis (subquery)
SELECT
  v.registarska_oznaka,
  v.tip_vozila,
  v.vrsta_goriva,
  v.kapacitet_putnika,
  v.u_prometu,
  o.datum_servisa AS zadnji_servis,
  o.vrsta_servisa,
  o.opis_radova
FROM vozila v
LEFT JOIN odrzavanje_vozila o
  ON o.id = (
    SELECT o2.id
    FROM odrzavanje_vozila o2
    WHERE o2.vozilo_id = v.id
    ORDER BY o2.datum_servisa DESC, o2.id DESC
    LIMIT 1
  )
WHERE v.u_prometu = 0
ORDER BY o.datum_servisa DESC;

-- 20) Score linije: pritužbe + broj polazaka
SELECT
  l.oznaka,
  l.naziv,
  COUNT(DISTINCT pr.id) AS prituzbe,
  COUNT(DISTINCT vr.id) AS polasci,
  (COUNT(DISTINCT pr.id) * 3 + COUNT(DISTINCT vr.id)) AS score
FROM linije l
LEFT JOIN prituzbe pr ON pr.linija_id = l.id
LEFT JOIN vozni_red vr ON vr.linija_id = l.id
GROUP BY l.id, l.oznaka, l.naziv
ORDER BY score DESC, prituzbe DESC, polasci DESC;


-- =========================================================
-- 2) 10 FUNKCIJA (UDF)
-- =========================================================
DELIMITER $$

DROP FUNCTION IF EXISTS fn_dob $$
CREATE FUNCTION fn_dob(p_datum_rodenja DATE)
RETURNS INT
DETERMINISTIC
BEGIN
  IF p_datum_rodenja IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN TIMESTAMPDIFF(YEAR, p_datum_rodenja, CURDATE());
END $$

DROP FUNCTION IF EXISTS fn_popust_korisnika $$
CREATE FUNCTION fn_popust_korisnika(p_korisnik_id INT)
RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
  DECLARE v_popust DECIMAL(5,2);

  SELECT kp.postotak_popusta
    INTO v_popust
  FROM korisnici u
  JOIN kategorija_putnik kp ON kp.id = u.kategorija_id
  WHERE u.id = p_korisnik_id;

  RETURN IFNULL(v_popust, 0);
END $$

DROP FUNCTION IF EXISTS fn_cijena_karte $$
CREATE FUNCTION fn_cijena_karte(p_korisnik_id INT, p_tip_karte_id INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
  DECLARE v_osnovna DECIMAL(10,2);
  DECLARE v_popust DECIMAL(5,2);

  SELECT osnovna_cijena INTO v_osnovna
  FROM tip_karte
  WHERE id = p_tip_karte_id;

  SET v_popust = fn_popust_korisnika(p_korisnik_id);

  RETURN ROUND(v_osnovna * (1 - (v_popust / 100)), 2);
END $$

DROP FUNCTION IF EXISTS fn_vrijedi_do $$
CREATE FUNCTION fn_vrijedi_do(p_datum_kupnje DATETIME, p_tip_karte_id INT)
RETURNS DATETIME
DETERMINISTIC
BEGIN
  DECLARE v_trajanje INT;

  SELECT trajanje_minute INTO v_trajanje
  FROM tip_karte
  WHERE id = p_tip_karte_id;

  RETURN DATE_ADD(p_datum_kupnje, INTERVAL v_trajanje MINUTE);
END $$

DROP FUNCTION IF EXISTS fn_is_ticket_valid $$
CREATE FUNCTION fn_is_ticket_valid(p_karta_kod VARCHAR(50), p_u_trenutku DATETIME)
RETURNS TINYINT
DETERMINISTIC
BEGIN
  DECLARE v_cnt INT;

  SELECT COUNT(*)
    INTO v_cnt
  FROM karta
  WHERE karta_kod = p_karta_kod
    AND p_u_trenutku BETWEEN datum_kupnje AND vrijedi_do;

  RETURN IF(v_cnt > 0, 1, 0);
END $$

DROP FUNCTION IF EXISTS fn_linija_broj_stanica $$
CREATE FUNCTION fn_linija_broj_stanica(p_linija_id INT)
RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE v_cnt INT;

  SELECT COUNT(*) INTO v_cnt
  FROM linije_stanice
  WHERE linija_id = p_linija_id;

  RETURN IFNULL(v_cnt, 0);
END $$

DROP FUNCTION IF EXISTS fn_linija_broj_zona $$
CREATE FUNCTION fn_linija_broj_zona(p_linija_id INT)
RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE v_cnt INT;

  SELECT COUNT(DISTINCT s.zona_id) INTO v_cnt
  FROM linije_stanice ls
  JOIN stanice s ON s.id = ls.stanica_id
  WHERE ls.linija_id = p_linija_id;

  RETURN IFNULL(v_cnt, 0);
END $$

DROP FUNCTION IF EXISTS fn_next_departure $$
CREATE FUNCTION fn_next_departure(p_linija_id INT, p_after TIME, p_kalendar_id INT)
RETURNS TIME
DETERMINISTIC
BEGIN
  DECLARE v_t TIME;

  SELECT MIN(vr.vrijeme_polaska) INTO v_t
  FROM vozni_red vr
  WHERE vr.linija_id = p_linija_id
    AND vr.kalendar_id = p_kalendar_id
    AND vr.vrijeme_polaska > p_after;

  RETURN v_t;
END $$

DROP FUNCTION IF EXISTS fn_servis_trosak_godina $$
CREATE FUNCTION fn_servis_trosak_godina(p_vozilo_id INT, p_godina INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
  DECLARE v_sum DECIMAL(10,2);

  SELECT ROUND(IFNULL(SUM(o.trosak_servisa), 0), 2) INTO v_sum
  FROM odrzavanje_vozila o
  WHERE o.vozilo_id = p_vozilo_id
    AND YEAR(o.datum_servisa) = p_godina;

  RETURN v_sum;
END $$

DROP FUNCTION IF EXISTS fn_neplacene_kazne $$
CREATE FUNCTION fn_neplacene_kazne(p_korisnik_id INT)
RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE v_cnt INT;

  SELECT COUNT(*) INTO v_cnt
  FROM prekrsaji
  WHERE korisnik_id = p_korisnik_id
    AND status_placanja = 'Neplaćeno';

  RETURN IFNULL(v_cnt, 0);
END $$

DELIMITER ;


-- =========================================================
-- 3) 15 PROCEDURA
-- =========================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_kupi_kartu $$
CREATE PROCEDURE sp_kupi_kartu(
  IN p_korisnik_id INT,
  IN p_tip_kod VARCHAR(20),
  OUT p_karta_id INT,
  OUT p_karta_kod VARCHAR(50)
)
BEGIN
  DECLARE v_tip_id INT;
  DECLARE v_now DATETIME;
  DECLARE v_kod VARCHAR(50);
  DECLARE v_status ENUM('Aktivan','Neaktivan','Suspendiran');

  SELECT status_racuna INTO v_status
  FROM korisnici
  WHERE id = p_korisnik_id;

  IF v_status <> 'Aktivan' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Korisnik nema aktivan račun.';
  END IF;

  SELECT id INTO v_tip_id
  FROM tip_karte
  WHERE tip_kod = p_tip_kod;

  IF v_tip_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nepostojeći tip_kod.';
  END IF;

  SET v_now = NOW();
  SET v_kod = CONCAT('K-', LPAD(FLOOR(RAND()*999999), 6, '0'), '-', DATE_FORMAT(v_now, '%Y%m%d%H%i%S'));

  INSERT INTO karta (tip_karte_id, korisnik_id, karta_kod, datum_kupnje, vrijedi_do, placena_cijena)
  VALUES (
    v_tip_id,
    p_korisnik_id,
    v_kod,
    v_now,
    fn_vrijedi_do(v_now, v_tip_id),
    fn_cijena_karte(p_korisnik_id, v_tip_id)
  );

  SET p_karta_id = LAST_INSERT_ID();
  SET p_karta_kod = v_kod;
END $$

DROP PROCEDURE IF EXISTS sp_izdaj_prekrsaj $$
CREATE PROCEDURE sp_izdaj_prekrsaj(
  IN p_korisnik_id INT,
  IN p_kontrolor_id INT,
  IN p_iznos DECIMAL(10,2),
  IN p_napomena TEXT,
  OUT p_prekrsaj_id INT
)
BEGIN
  IF p_iznos <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Iznos kazne mora biti > 0.';
  END IF;

  INSERT INTO prekrsaji (korisnik_id, zaposlenik_id, datum_prekrsaja, iznos_kazne, status_placanja, napomena)
  VALUES (p_korisnik_id, p_kontrolor_id, NOW(), p_iznos, 'Neplaćeno', p_napomena);

  SET p_prekrsaj_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_plati_prekrsaj $$
CREATE PROCEDURE sp_plati_prekrsaj(IN p_prekrsaj_id INT)
BEGIN
  UPDATE prekrsaji
  SET status_placanja = 'Plaćeno'
  WHERE id = p_prekrsaj_id;
END $$

DROP PROCEDURE IF EXISTS sp_promijeni_status_korisnika $$
CREATE PROCEDURE sp_promijeni_status_korisnika(
  IN p_korisnik_id INT,
  IN p_status ENUM('Aktivan','Neaktivan','Suspendiran')
)
BEGIN
  UPDATE korisnici
  SET status_racuna = p_status
  WHERE id = p_korisnik_id;
END $$

DROP PROCEDURE IF EXISTS sp_dodaj_prituzbu $$
CREATE PROCEDURE sp_dodaj_prituzbu(
  IN p_korisnik_id INT,
  IN p_linija_oznaka VARCHAR(10),
  IN p_kategorija ENUM('Kašnjenje', 'Ponašanje osoblja', 'Čistoća', 'Kvar vozila', 'Ostalo'),
  IN p_tekst TEXT,
  OUT p_prituzba_id INT
)
BEGIN
  DECLARE v_linija_id INT;

  IF p_linija_oznaka IS NULL OR p_linija_oznaka = '' THEN
    SET v_linija_id = NULL;
  ELSE
    SELECT id INTO v_linija_id
    FROM linije
    WHERE oznaka = p_linija_oznaka;
  END IF;

  INSERT INTO prituzbe (korisnik_id, linija_id, datum_prituzbe, kategorija_prituzbe, tekst_prituzbe, status_rjesavanja)
  VALUES (p_korisnik_id, v_linija_id, NOW(), p_kategorija, p_tekst, 'Novo');

  SET p_prituzba_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_rijesi_prituzbu $$
CREATE PROCEDURE sp_rijesi_prituzbu(
  IN p_prituzba_id INT,
  IN p_status ENUM('Novo','U obradi','Riješeno','Odbačeno')
)
BEGIN
  UPDATE prituzbe
  SET status_rjesavanja = p_status
  WHERE id = p_prituzba_id;
END $$

DROP PROCEDURE IF EXISTS sp_zakazi_servis $$
CREATE PROCEDURE sp_zakazi_servis(
  IN p_reg VARCHAR(10),
  IN p_mehanicar_id INT,
  IN p_datum DATE,
  IN p_vrsta ENUM('Redovni', 'Izvanredni', 'Tehnički pregled', 'Popravak kvar'),
  IN p_trosak DECIMAL(10,2),
  IN p_opis TEXT,
  OUT p_servis_id INT
)
BEGIN
  DECLARE v_vozilo_id INT;

  SELECT id INTO v_vozilo_id
  FROM vozila
  WHERE registarska_oznaka = p_reg;

  IF v_vozilo_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nepostojeće vozilo (registarska_oznaka).';
  END IF;

  INSERT INTO odrzavanje_vozila (vozilo_id, zaposlenik_id, datum_servisa, vrsta_servisa, trosak_servisa, opis_radova)
  VALUES (v_vozilo_id, p_mehanicar_id, p_datum, p_vrsta, p_trosak, p_opis);

  SET p_servis_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_oznaj_vozilo_van_prometa $$
CREATE PROCEDURE sp_oznaj_vozilo_van_prometa(
  IN p_reg VARCHAR(10),
  IN p_u_prometu BOOLEAN
)
BEGIN
  UPDATE vozila
  SET u_prometu = p_u_prometu
  WHERE registarska_oznaka = p_reg;
END $$

DROP PROCEDURE IF EXISTS sp_dodaj_vozni_red $$
CREATE PROCEDURE sp_dodaj_vozni_red(
  IN p_linija_oznaka VARCHAR(10),
  IN p_reg VARCHAR(10),
  IN p_vozac_broj VARCHAR(20),
  IN p_kalendar_naziv VARCHAR(50),
  IN p_vrijeme TIME,
  OUT p_vozni_red_id INT
)
BEGIN
  DECLARE v_linija_id INT;
  DECLARE v_vozilo_id INT;
  DECLARE v_vozac_id INT;
  DECLARE v_kalendar_id INT;

  SELECT id INTO v_linija_id FROM linije WHERE oznaka = p_linija_oznaka;
  SELECT id INTO v_vozilo_id FROM vozila WHERE registarska_oznaka = p_reg;
  SELECT id INTO v_vozac_id FROM zaposlenik WHERE zaposlenik_broj = p_vozac_broj;
  SELECT id INTO v_kalendar_id FROM kalendari WHERE kalendar_naziv = p_kalendar_naziv;

  IF v_linija_id IS NULL OR v_vozilo_id IS NULL OR v_vozac_id IS NULL OR v_kalendar_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Neispravni ulazni podaci za vozni red.';
  END IF;

  INSERT INTO vozni_red (linija_id, vozilo_id, vozac_id, kalendar_id, vrijeme_polaska)
  VALUES (v_linija_id, v_vozilo_id, v_vozac_id, v_kalendar_id, p_vrijeme);

  SET p_vozni_red_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_premjesti_stanicu_u_zonu $$
CREATE PROCEDURE sp_premjesti_stanicu_u_zonu(
  IN p_stanica_id INT,
  IN p_zona_kod VARCHAR(10)
)
BEGIN
  DECLARE v_zona_id INT;

  SELECT id INTO v_zona_id
  FROM zone
  WHERE zona_kod = p_zona_kod;

  IF v_zona_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nepostojeća zona_kod.';
  END IF;

  UPDATE stanice
  SET zona_id = v_zona_id
  WHERE id = p_stanica_id;
END $$

DROP PROCEDURE IF EXISTS sp_dodaj_stanicu_na_liniju $$
CREATE PROCEDURE sp_dodaj_stanicu_na_liniju(
  IN p_linija_oznaka VARCHAR(10),
  IN p_stanica_naziv VARCHAR(100),
  IN p_redoslijed INT
)
BEGIN
  DECLARE v_linija_id INT;
  DECLARE v_stanica_id INT;

  SELECT id INTO v_linija_id FROM linije WHERE oznaka = p_linija_oznaka;
  SELECT id INTO v_stanica_id FROM stanice WHERE naziv = p_stanica_naziv;

  IF v_linija_id IS NULL OR v_stanica_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Linija ili stanica ne postoji.';
  END IF;

  INSERT INTO linije_stanice (linija_id, stanica_id, redoslijed)
  VALUES (v_linija_id, v_stanica_id, p_redoslijed);
END $$

DROP PROCEDURE IF EXISTS sp_ukloni_stanicu_s_linije $$
CREATE PROCEDURE sp_ukloni_stanicu_s_linije(
  IN p_linija_oznaka VARCHAR(10),
  IN p_stanica_id INT
)
BEGIN
  DECLARE v_linija_id INT;
  SELECT id INTO v_linija_id FROM linije WHERE oznaka = p_linija_oznaka;

  DELETE FROM linije_stanice
  WHERE linija_id = v_linija_id
    AND stanica_id = p_stanica_id;
END $$

DROP PROCEDURE IF EXISTS sp_izracunaj_prihod_period $$
CREATE PROCEDURE sp_izracunaj_prihod_period(
  IN p_od DATETIME,
  IN p_do DATETIME
)
BEGIN
  SELECT
    COUNT(*) AS broj_karata,
    ROUND(SUM(placena_cijena), 2) AS prihod
  FROM karta
  WHERE datum_kupnje BETWEEN p_od AND p_do;
END $$

DROP PROCEDURE IF EXISTS sp_top_linije_po_prituzbama $$
CREATE PROCEDURE sp_top_linije_po_prituzbama(IN p_limit INT)
BEGIN
  SELECT
    l.oznaka,
    l.naziv,
    COUNT(*) AS broj_prituzbi
  FROM prituzbe pr
  JOIN linije l ON l.id = pr.linija_id
  GROUP BY l.id, l.oznaka, l.naziv
  ORDER BY broj_prituzbi DESC
  LIMIT p_limit;
END $$

DROP PROCEDURE IF EXISTS sp_prekrsaji_po_korisniku $$
CREATE PROCEDURE sp_prekrsaji_po_korisniku(IN p_korisnik_id INT)
BEGIN
  SELECT
    p.id,
    p.datum_prekrsaja,
    p.iznos_kazne,
    p.status_placanja,
    CONCAT(z.ime,' ',z.prezime) AS kontrolor
  FROM prekrsaji p
  JOIN zaposlenik z ON z.id = p.zaposlenik_id
  WHERE p.korisnik_id = p_korisnik_id
  ORDER BY p.datum_prekrsaja DESC;
END $$

DROP PROCEDURE IF EXISTS sp_vozilo_servisi_u_godini $$
CREATE PROCEDURE sp_vozilo_servisi_u_godini(IN p_reg VARCHAR(10), IN p_godina INT)
BEGIN
  SELECT
    v.registarska_oznaka,
    o.datum_servisa,
    o.vrsta_servisa,
    o.trosak_servisa,
    CONCAT(z.ime,' ',z.prezime) AS mehanicar
  FROM vozila v
  JOIN odrzavanje_vozila o ON o.vozilo_id = v.id
  JOIN zaposlenik z ON z.id = o.zaposlenik_id
  WHERE v.registarska_oznaka = p_reg
    AND YEAR(o.datum_servisa) = p_godina
  ORDER BY o.datum_servisa DESC;
END $$

DELIMITER ;


-- =========================================================
-- 4) 10 TRIGGERA (bez log tablica)
-- =========================================================
DELIMITER $$

DROP TRIGGER IF EXISTS trg_karta_bi_set_defaults $$
CREATE TRIGGER trg_karta_bi_set_defaults
BEFORE INSERT ON karta
FOR EACH ROW
BEGIN
  DECLARE v_status ENUM('Aktivan','Neaktivan','sp_plati_prekrsajSuspendiran');

  SELECT status_racuna INTO v_status
  FROM korisnici
  WHERE id = NEW.korisnik_id;

  IF v_status <> 'Aktivan' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Korisnik nema aktivan račun (karta).';
  END IF;

  IF NEW.datum_kupnje IS NULL THEN
    SET NEW.datum_kupnje = NOW();
  END IF;

  IF NEW.vrijedi_do IS NULL THEN
    SET NEW.vrijedi_do = fn_vrijedi_do(NEW.datum_kupnje, NEW.tip_karte_id);
  END IF;

  IF NEW.placena_cijena IS NULL OR NEW.placena_cijena < 0 THEN
    SET NEW.placena_cijena = fn_cijena_karte(NEW.korisnik_id, NEW.tip_karte_id);
  END IF;

  IF NEW.karta_kod IS NULL OR NEW.karta_kod = '' THEN
    SET NEW.karta_kod = CONCAT('K-', LPAD(FLOOR(RAND()*999999), 6, '0'), '-', DATE_FORMAT(NEW.datum_kupnje, '%Y%m%d%H%i%S'));
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_karta_bu_no_negative_price $$
CREATE TRIGGER trg_karta_bu_no_negative_price
BEFORE UPDATE ON karta
FOR EACH ROW
BEGIN
  IF NEW.placena_cijena < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'placena_cijena ne može biti negativna.';
  END IF;

  IF NEW.vrijedi_do < NEW.datum_kupnje THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vrijedi_do ne može biti prije datum_kupnje.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_prekrsaji_bi_defaults $$
CREATE TRIGGER trg_prekrsaji_bi_defaults
BEFORE INSERT ON prekrsaji
FOR EACH ROW
BEGIN
  IF NEW.datum_prekrsaja IS NULL THEN
    SET NEW.datum_prekrsaja = NOW();
  END IF;

  IF NEW.status_placanja IS NULL OR NEW.status_placanja = '' THEN
    SET NEW.status_placanja = 'Neplaćeno';
  END IF;

  IF NEW.iznos_kazne IS NULL OR NEW.iznos_kazne <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Iznos kazne mora biti > 0.';
  END IF;

  IF NEW.iznos_kazne < 50.00 THEN
    SET NEW.iznos_kazne = 50.00;
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_prekrsaji_bu_guard_status $$
CREATE TRIGGER trg_prekrsaji_bu_guard_status
BEFORE UPDATE ON prekrsaji
FOR EACH ROW
BEGIN
  IF OLD.status_placanja = 'Plaćeno' AND NEW.status_placanja <> 'Plaćeno' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ne može se vraćati status s Plaćeno na drugo.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_odrzavanje_bi_only_mehanicar $$
CREATE TRIGGER trg_odrzavanje_bi_only_mehanicar
BEFORE INSERT ON odrzavanje_vozila
FOR EACH ROW
BEGIN
  DECLARE v_uloga VARCHAR(100);

  SELECT naziv_uloge INTO v_uloga
  FROM zaposlenik
  WHERE id = NEW.zaposlenik_id;

  IF v_uloga <> 'Mehaničar' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Održavanje može evidentirati samo Mehaničar.';
  END IF;

  IF NEW.trosak_servisa IS NULL OR NEW.trosak_servisa < 0 THEN
    SET NEW.trosak_servisa = 0;
  END IF;

  IF NEW.datum_servisa IS NULL THEN
    SET NEW.datum_servisa = CURDATE();
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_odrzavanje_ai_out_of_service $$
CREATE TRIGGER trg_odrzavanje_ai_out_of_service
AFTER INSERT ON odrzavanje_vozila
FOR EACH ROW
BEGIN
  IF NEW.vrsta_servisa = 'Popravak kvar' AND NEW.trosak_servisa >= 1500 THEN
    UPDATE vozila
    SET u_prometu = 0
    WHERE id = NEW.vozilo_id;
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_vozni_red_bi_validate $$
CREATE TRIGGER trg_vozni_red_bi_validate
BEFORE INSERT ON vozni_red
FOR EACH ROW
BEGIN
  DECLARE v_u_prometu BOOLEAN;
  DECLARE v_uloga VARCHAR(100);

  SELECT u_prometu INTO v_u_prometu
  FROM vozila
  WHERE id = NEW.vozilo_id;

  IF v_u_prometu = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vozilo je van prometa (ne može u vozni red).';
  END IF;

  SELECT naziv_uloge INTO v_uloga
  FROM zaposlenik
  WHERE id = NEW.vozac_id;

  IF v_uloga <> 'Vozač' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vozni_red.vozac_id mora biti uloga Vozač.';
  END IF;

  IF NEW.vrijeme_polaska IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vrijeme_polaska je obavezno.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_vozni_red_bu_validate $$
CREATE TRIGGER trg_vozni_red_bu_validate
BEFORE UPDATE ON vozni_red
FOR EACH ROW
BEGIN
  IF NEW.vrijeme_polaska IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vrijeme_polaska ne smije biti NULL.';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_prituzbe_bi_defaults $$
CREATE TRIGGER trg_prituzbe_bi_defaults
BEFORE INSERT ON prituzbe
FOR EACH ROW
BEGIN
  IF NEW.datum_prituzbe IS NULL THEN
    SET NEW.datum_prituzbe = NOW();
  END IF;

  IF NEW.status_rjesavanja IS NULL OR NEW.status_rjesavanja = '' THEN
    SET NEW.status_rjesavanja = 'Novo';
  END IF;

  IF NEW.kategorija_prituzbe = 'Kvar vozila' THEN
    SET NEW.status_rjesavanja = 'U obradi';
  END IF;
END $$

DROP TRIGGER IF EXISTS trg_korisnici_bu_suspend_if_many_unpaid $$
CREATE TRIGGER trg_korisnici_bu_suspend_if_many_unpaid
BEFORE UPDATE ON korisnici
FOR EACH ROW
BEGIN
  DECLARE v_unpaid INT;

  IF NEW.status_racuna = 'Aktivan' THEN
    SELECT COUNT(*) INTO v_unpaid
    FROM prekrsaji
    WHERE korisnik_id = OLD.id
      AND status_placanja = 'Neplaćeno';

    IF v_unpaid >= 3 THEN
      SET NEW.status_racuna = 'Suspendiran';
    END IF;
  END IF;
END $$

DELIMITER ;


-- =========================================================
-- 5) 10 VIEW-ova
-- =========================================================
CREATE OR REPLACE VIEW v_korisnici_s_popustom AS
SELECT
  u.id AS korisnik_id,
  u.ime, u.prezime, u.email,
  u.datum_rodenja,
  fn_dob(u.datum_rodenja) AS dob,
  u.status_racuna,
  kp.kategorija_kod,
  kp.kategorija_naziv,
  kp.postotak_popusta
FROM korisnici u
JOIN kategorija_putnik kp ON kp.id = u.kategorija_id;

CREATE OR REPLACE VIEW v_aktivne_karte AS
SELECT
  k.id AS karta_id,
  k.karta_kod,
  k.datum_kupnje,
  k.vrijedi_do,
  k.placena_cijena,
  u.id AS korisnik_id,
  CONCAT(u.ime,' ',u.prezime) AS korisnik,
  tk.tip_kod,
  tk.tip_naziv
FROM karta k
JOIN korisnici u ON u.id = k.korisnik_id
JOIN tip_karte tk ON tk.id = k.tip_karte_id
WHERE NOW() BETWEEN k.datum_kupnje AND k.vrijedi_do;

CREATE OR REPLACE VIEW v_prekrsaji_otvoreni AS
SELECT
  p.id AS prekrsaj_id,
  p.datum_prekrsaja,
  p.iznos_kazne,
  p.status_placanja,
  u.id AS korisnik_id,
  CONCAT(u.ime,' ',u.prezime) AS korisnik,
  z.zaposlenik_broj AS kontrolor_broj,
  CONCAT(z.ime,' ',z.prezime) AS kontrolor
FROM prekrsaji p
JOIN korisnici u ON u.id = p.korisnik_id
JOIN zaposlenik z ON z.id = p.zaposlenik_id
WHERE p.status_placanja <> 'Plaćeno';

CREATE OR REPLACE VIEW v_prihod_po_danu AS
SELECT
  DATE(k.datum_kupnje) AS dan,
  COUNT(*) AS broj_karata,
  ROUND(SUM(k.placena_cijena), 2) AS prihod
FROM karta k
GROUP BY DATE(k.datum_kupnje)
ORDER BY dan DESC;

CREATE OR REPLACE VIEW v_servisi_po_vozilu AS
SELECT
  v.id AS vozilo_id,
  v.registarska_oznaka,
  v.tip_vozila,
  v.u_prometu,
  MAX(o.datum_servisa) AS zadnji_servis,
  ROUND(IFNULL(SUM(o.trosak_servisa), 0), 2) AS trosak_ukupno
FROM vozila v
LEFT JOIN odrzavanje_vozila o ON o.vozilo_id = v.id
GROUP BY v.id, v.registarska_oznaka, v.tip_vozila, v.u_prometu;

CREATE OR REPLACE VIEW v_linije_osnovno AS
SELECT
  l.id AS linija_id,
  l.oznaka,
  l.naziv,
  l.tip_linije,
  l.duljina_km,
  fn_linija_broj_stanica(l.id) AS broj_stanica,
  fn_linija_broj_zona(l.id) AS broj_zona
FROM linije l;

CREATE OR REPLACE VIEW v_vozni_red_detaljno AS
SELECT
  vr.id AS vozni_red_id,
  l.oznaka AS linija,
  l.naziv AS naziv_linije,
  vr.vrijeme_polaska,
  k.kalendar_naziv,
  v.registarska_oznaka,
  v.tip_vozila,
  CONCAT(z.ime,' ',z.prezime) AS vozac,
  z.zaposlenik_broj AS vozac_broj
FROM vozni_red vr
JOIN linije l ON l.id = vr.linija_id
JOIN kalendari k ON k.id = vr.kalendar_id
JOIN vozila v ON v.id = vr.vozilo_id
JOIN zaposlenik z ON z.id = vr.vozac_id;

CREATE OR REPLACE VIEW v_prituzbe_otvorene_detaljno AS
SELECT
  pr.id AS prituzba_id,
  pr.datum_prituzbe,
  pr.kategorija_prituzbe,
  pr.status_rjesavanja,
  CONCAT(u.ime,' ',u.prezime) AS korisnik,
  u.email,
  l.oznaka AS linija,
  l.naziv AS naziv_linije,
  pr.tekst_prituzbe
FROM prituzbe pr
JOIN korisnici u ON u.id = pr.korisnik_id
LEFT JOIN linije l ON l.id = pr.linija_id
WHERE pr.status_rjesavanja IN ('Novo','U obradi');

CREATE OR REPLACE VIEW v_zaposlenici_uloge_broj AS
SELECT
  naziv_uloge,
  COUNT(*) AS broj
FROM zaposlenik
GROUP BY naziv_uloge
ORDER BY broj DESC;

CREATE OR REPLACE VIEW v_vozila_status_servis AS
SELECT
  v.registarska_oznaka,
  v.tip_vozila,
  v.vrsta_goriva,
  v.kapacitet_putnika,
  v.u_prometu,
  s.zadnji_servis,
  s.trosak_ukupno
FROM vozila v
LEFT JOIN v_servisi_po_vozilu s ON s.vozilo_id = v.id;

USE gradski_prijevoz;
DELIMITER //

-- Trigger: prekršaji – automatska suspenzija nakon 3 neplaćena
-- Ideja: kad ubaciš novi prekršaj, sustav automatski suspendira korisnika ako ima 3+ neplaćena.
DELIMITER //

DROP TRIGGER IF EXISTS trg_prekrsaj_after_insert_suspend //

CREATE TRIGGER trg_prekrsaj_after_insert_suspend
AFTER INSERT ON prekrsaji
FOR EACH ROW
BEGIN
  DECLARE v_neplacenih INT;

  SELECT COUNT(*)
    INTO v_neplacenih
  FROM prekrsaji
  WHERE korisnik_id = NEW.korisnik_id
    AND status_placanja = 'Neplaćeno';

  IF v_neplacenih >= 3 THEN
    UPDATE korisnici
    SET status_racuna = 'Suspendiran'
    WHERE id = NEW.korisnik_id
      AND status_racuna != 'Suspendiran';
  END IF;
END //

DELIMITER ;

INSERT INTO prekrsaji (korisnik_id, zaposlenik_id, datum_prekrsaja, iznos_kazne, status_placanja, napomena)
	VALUES (3, 5, NOW(), 50.00, 'Neplaćeno', 'TEST 1');

INSERT INTO prekrsaji (korisnik_id, zaposlenik_id, datum_prekrsaja, iznos_kazne, status_placanja, napomena)
	VALUES (3, 5, NOW(), 50.00, 'Neplaćeno', 'TEST 2');

INSERT INTO prekrsaji (korisnik_id, zaposlenik_id, datum_prekrsaja, iznos_kazne, status_placanja, napomena)
	VALUES (3, 5, NOW(), 50.00, 'Neplaćeno', 'TEST 3');
  
SELECT id, status_racuna FROM korisnici WHERE id = 3;

-- ============================================================
-- PROCEDURA: sp_zakazi_servis
-- Opis: Zakazuje servis vozila na temelju registarske oznake.
--       Provjerava postoji li vozilo i upisuje servis.
-- ============================================================

DROP PROCEDURE IF EXISTS sp_zakazi_servis;
DELIMITER $$

CREATE PROCEDURE sp_zakazi_servis(
  IN p_reg VARCHAR(10),
  IN p_mehanicar_id INT,
  IN p_datum DATE,
  IN p_vrsta ENUM('Redovni', 'Izvanredni', 'Tehnički pregled', 'Popravak kvar'),
  IN p_trosak DECIMAL(10,2),
  IN p_opis TEXT,
  OUT p_servis_id INT
)
BEGIN
  DECLARE v_vozilo_id INT;

  SELECT id INTO v_vozilo_id
  FROM vozila
  WHERE registarska_oznaka = p_reg;

  IF v_vozilo_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Nepostojeće vozilo (registarska_oznaka).';
  END IF;

  INSERT INTO odrzavanje_vozila (
    vozilo_id,
    zaposlenik_id,
    datum_servisa,
    vrsta_servisa,
    trosak_servisa,
    opis_radova
  )
  VALUES (
    v_vozilo_id,
    p_mehanicar_id,
    p_datum,
    p_vrsta,
    p_trosak,
    p_opis
  );

  SET p_servis_id = LAST_INSERT_ID();
END $$

DELIMITER ;

-- TEST
CALL sp_zakazi_servis(
  'ZG-101-AU',
  8,
  CURDATE(),
  'Redovni',
  150.00,
  'TEST servis',
  @servis_id
);

SELECT @servis_id;
SELECT * FROM odrzavanje_vozila ORDER BY id DESC LIMIT 1;

-- ============================================================
-- PROCEDURA: sp_dodaj_prituzbu
-- Opis: Dodaje novu pritužbu korisnika.
--       Linija je opcionalna (može biti NULL).
-- ============================================================

DROP PROCEDURE IF EXISTS sp_dodaj_prituzbu;
DELIMITER $$

CREATE PROCEDURE sp_dodaj_prituzbu(
  IN p_korisnik_id INT,
  IN p_linija_oznaka VARCHAR(10),
  IN p_kategorija ENUM('Kašnjenje','Ponašanje osoblja','Čistoća','Kvar vozila','Ostalo'),
  IN p_tekst TEXT,
  OUT p_prituzba_id INT
)
BEGIN
  DECLARE v_linija_id INT;

  IF p_linija_oznaka IS NULL OR p_linija_oznaka = '' THEN
    SET v_linija_id = NULL;
  ELSE
    SELECT id INTO v_linija_id
    FROM linije
    WHERE oznaka = p_linija_oznaka;
  END IF;

  INSERT INTO prituzbe (
    korisnik_id,
    linija_id,
    datum_prituzbe,
    kategorija_prituzbe,
    tekst_prituzbe,
    status_rjesavanja
  )
  VALUES (
    p_korisnik_id,
    v_linija_id,
    NOW(),
    p_kategorija,
    p_tekst,
    'Novo'
  );

  SET p_prituzba_id = LAST_INSERT_ID();
END $$

DELIMITER ;

-- TEST
CALL sp_dodaj_prituzbu(
  1,
  '1',
  'Kašnjenje',
  'TEST pritužba',
  @prituzba_id
);

SELECT @prituzba_id;
SELECT * FROM prituzbe ORDER BY id DESC LIMIT 1;

-- ============================================================
-- PROCEDURA: sp_podmiri_kazne_korisnika
-- Opis:
--   - Označi SVE neplaćene prekršaje korisnika kao "Plaćeno"
--   - Ako nakon toga korisnik nema više neplaćenih, a bio je suspendiran -> reaktiviraj ga
--   - Vraća broj ažuriranih prekršaja i poruku
--
-- Tablice koje koristi (postoje u tvojoj skripti):
--   korisnici, prekrsaji
-- ============================================================

DROP PROCEDURE IF EXISTS sp_podmiri_kazne_korisnika;
DELIMITER $$

CREATE PROCEDURE sp_podmiri_kazne_korisnika(
  IN p_korisnik_id INT,
  OUT p_broj_placenih INT,
  OUT p_korisnik_reaktiviran BOOLEAN,
  OUT p_poruka VARCHAR(255)
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_preostalo_neplacenih INT;

  -- default
  SET p_broj_placenih = 0;
  SET p_korisnik_reaktiviran = FALSE;

  START TRANSACTION;

  -- provjeri korisnika
  SELECT status_racuna INTO v_status
  FROM korisnici
  WHERE id = p_korisnik_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    ROLLBACK;
    SET p_poruka = 'Greška: korisnik ne postoji.';
  ELSE
    -- plati sve neplaćene
    UPDATE prekrsaji
    SET status_placanja = 'Plaćeno'
    WHERE korisnik_id = p_korisnik_id
      AND status_placanja = 'Neplaćeno';

    SET p_broj_placenih = ROW_COUNT();

    -- provjeri je li ostalo neplaćenih
    SELECT COUNT(*) INTO v_preostalo_neplacenih
    FROM prekrsaji
    WHERE korisnik_id = p_korisnik_id
      AND status_placanja = 'Neplaćeno';

    -- reaktiviraj ako je bio suspendiran i više nema neplaćenih
    IF v_status = 'Suspendiran' AND v_preostalo_neplacenih = 0 THEN
      UPDATE korisnici
      SET status_racuna = 'Aktivan'
      WHERE id = p_korisnik_id;

      SET p_korisnik_reaktiviran = TRUE;
    END IF;

    COMMIT;

    SET p_poruka = CONCAT(
      'Plaćeno prekršaja: ', p_broj_placenih,
      '. Preostalo neplaćenih: ', v_preostalo_neplacenih,
      CASE WHEN p_korisnik_reaktiviran THEN '. Korisnik reaktiviran.' ELSE '' END
    );
  END IF;
END $$

DELIMITER ;

-- 1) napravi da korisnik 3 ima bar 2 neplaćena (ili koristi nekog tko već ima)
INSERT INTO prekrsaji (korisnik_id, zaposlenik_id, datum_prekrsaja, iznos_kazne, status_placanja, napomena)
VALUES
(3, 5, NOW(), 50.00, 'Neplaćeno', 'TEST uplata 1'),
(3, 5, NOW(), 50.00, 'Neplaćeno', 'TEST uplata 2');

-- (opcionalno) suspendiraj korisnika da vidiš reaktivaciju
UPDATE korisnici SET status_racuna = 'Suspendiran' WHERE id = 3;

-- 2) pozovi proceduru
CALL sp_podmiri_kazne_korisnika(3, @placeno, @reakt, @poruka);
SELECT @placeno AS placeno, @reakt AS reaktiviran, @poruka AS poruka;

-- 3) provjere
SELECT id, status_racuna FROM korisnici WHERE id = 3;
SELECT id, status_placanja, napomena FROM prekrsaji WHERE korisnik_id = 3 ORDER BY id DESC LIMIT 10;


-- ============================================================
-- PROCEDURA: sp_prijavi_servis_i_oznaci_van_prometa
-- Opis:
--   - Prijavi servis za vozilo (po registarskoj oznaci)
--   - Validira da vozilo i mehaničar postoje + trošak >= 0
--   - Ako je vrsta servisa "Izvanredni" ili "Popravak kvar":
--       automatski postavlja vozilo van prometa (u_prometu = 0)
--   - Sve u jednoj transakciji
--
-- Tablice koje koristi (postoje u tvojoj skripti):
--   vozila, zaposlenik, odrzavanje_vozila
-- ============================================================

DROP PROCEDURE IF EXISTS sp_prijavi_servis_i_oznaci_van_prometa;
DELIMITER $$

CREATE PROCEDURE sp_prijavi_servis_i_oznaci_van_prometa(
  IN p_reg VARCHAR(10),
  IN p_mehanicar_id INT,
  IN p_datum DATE,
  IN p_vrsta ENUM('Redovni', 'Izvanredni', 'Tehnički pregled', 'Popravak kvar'),
  IN p_trosak DECIMAL(10,2),
  IN p_opis TEXT,
  OUT p_servis_id INT,
  OUT p_vozilo_van_prometa BOOLEAN,
  OUT p_poruka VARCHAR(255)
)
BEGIN
  DECLARE v_vozilo_id INT;
  DECLARE v_reg VARCHAR(10);
  DECLARE v_mehanicar_ok INT;

  SET p_servis_id = NULL;
  SET p_vozilo_van_prometa = FALSE;

  IF p_trosak < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Trošak servisa ne smije biti negativan.';
  END IF;

  START TRANSACTION;

  -- Vozilo (lock da izbjegnemo race condition s u_prometu)
  SELECT id, registarska_oznaka INTO v_vozilo_id, v_reg
  FROM vozila
  WHERE registarska_oznaka = p_reg
  FOR UPDATE;

  IF v_vozilo_id IS NULL THEN
    ROLLBACK;
    SET p_poruka = 'Greška: nepostojeće vozilo (registarska_oznaka).';
  ELSE
    -- Mehaničar postoji?
    SELECT COUNT(*) INTO v_mehanicar_ok
    FROM zaposlenik
    WHERE id = p_mehanicar_id;

    IF v_mehanicar_ok = 0 THEN
      ROLLBACK;
      SET p_poruka = 'Greška: nepostojeći zaposlenik (mehaničar).';
    ELSE
      -- Unos servisa
      INSERT INTO odrzavanje_vozila (vozilo_id, zaposlenik_id, datum_servisa, vrsta_servisa, trosak_servisa, opis_radova)
      VALUES (v_vozilo_id, p_mehanicar_id, p_datum, p_vrsta, p_trosak, p_opis);

      SET p_servis_id = LAST_INSERT_ID();

      -- Ako je izvanredni ili kvar -> vozilo van prometa
      IF p_vrsta IN ('Izvanredni', 'Popravak kvar') THEN
        UPDATE vozila
        SET u_prometu = 0
        WHERE id = v_vozilo_id;

        SET p_vozilo_van_prometa = TRUE;
      END IF;

      COMMIT;

      SET p_poruka = CONCAT(
        'Servis prijavljen za vozilo ', v_reg,
        ' (ID servisa: ', p_servis_id, ').',
        CASE WHEN p_vozilo_van_prometa THEN ' Vozilo označeno van prometa.' ELSE '' END
      );
    END IF;
  END IF;
END $$

DELIMITER ;

-- ============================================================
-- TEST (primjer):
-- ============================================================
CALL sp_prijavi_servis_i_oznaci_van_prometa('ZG-101-AU', 8, CURDATE(), 'Popravak kvar', 250.00, 'TEST kvar', @sid, @van, @msg);
SELECT @sid AS servis_id, @van AS vozilo_van_prometa, @msg AS poruka;
SELECT id, registarska_oznaka, u_prometu FROM vozila WHERE registarska_oznaka = 'ZG-101-AU';
SELECT * FROM odrzavanje_vozila WHERE id = @sid;

-- ============================================================
-- POGLED: vw_korisnik_sazetak
-- Opis:
--   Sažetak po korisniku (dashboard):
--   - zadnja kupnja karte + zadnja cijena
--   - broj karata ukupno i u zadnjih 30 dana
--   - broj prekršaja ukupno i broj neplaćenih
--   - broj pritužbi ukupno i broj "otvorenih" (Novo/U obradi)
--   - zadnji prekršaj datum i iznos
--
-- Tablice: korisnici, karta, prekrsaji, prituzbe
-- Napomena: radi bez novih tablica; koristi agregacije + derived tablice.
-- ============================================================

DROP VIEW IF EXISTS vw_korisnik_sazetak;

CREATE VIEW vw_korisnik_sazetak AS
SELECT
  k.id AS korisnik_id,
  k.ime,
  k.prezime,
  k.email,
  k.status_racuna,

  -- Karte
  COALESCE(ka.ukupno_karata, 0) AS ukupno_karata,
  COALESCE(ka.karata_30d, 0) AS karata_zadnjih_30_dana,
  ka.zadnja_kupnja AS zadnja_kupnja_karte,
  ka.zadnja_cijena AS zadnja_placena_cijena,

  -- Prekršaji
  COALESCE(pr.ukupno_prekrsaja, 0) AS ukupno_prekrsaja,
  COALESCE(pr.neplaceno_prekrsaja, 0) AS neplaceno_prekrsaja,
  pr.zadnji_prekrsaj_datum AS zadnji_prekrsaj_datum,
  pr.zadnji_prekrsaj_iznos AS zadnji_prekrsaj_iznos,

  -- Pritužbe
  COALESCE(pt.ukupno_prituzbi, 0) AS ukupno_prituzbi,
  COALESCE(pt.otvoreno_prituzbi, 0) AS otvoreno_prituzbi

FROM korisnici k

LEFT JOIN (
  SELECT
    korisnik_id,
    COUNT(*) AS ukupno_karata,
    SUM(CASE WHEN datum_kupnje >= (NOW() - INTERVAL 30 DAY) THEN 1 ELSE 0 END) AS karata_30d,
    MAX(datum_kupnje) AS zadnja_kupnja,
    SUBSTRING_INDEX(
      GROUP_CONCAT(placena_cijena ORDER BY datum_kupnje DESC SEPARATOR ','), ',', 1
    ) + 0 AS zadnja_cijena
  FROM karta
  GROUP BY korisnik_id
) ka ON ka.korisnik_id = k.id

LEFT JOIN (
  SELECT
    korisnik_id,
    COUNT(*) AS ukupno_prekrsaja,
    SUM(CASE WHEN status_placanja = 'Neplaćeno' THEN 1 ELSE 0 END) AS neplaceno_prekrsaja,
    MAX(datum_prekrsaja) AS zadnji_prekrsaj_datum,
    SUBSTRING_INDEX(
      GROUP_CONCAT(iznos_kazne ORDER BY datum_prekrsaja DESC SEPARATOR ','), ',', 1
    ) + 0 AS zadnji_prekrsaj_iznos
  FROM prekrsaji
  GROUP BY korisnik_id
) pr ON pr.korisnik_id = k.id

LEFT JOIN (
  SELECT
    korisnik_id,
    COUNT(*) AS ukupno_prituzbi,
    SUM(CASE WHEN status_rjesavanja IN ('Novo','U obradi') THEN 1 ELSE 0 END) AS otvoreno_prituzbi
  FROM prituzbe
  GROUP BY korisnik_id
) pt ON pt.korisnik_id = k.id;

-- ============================================================
-- TEST:
-- ============================================================
-- 1) Top korisnici s najviše neplaćenih prekršaja:
SELECT korisnik_id, ime, prezime, neplaceno_prekrsaja, zadnji_prekrsaj_datum
FROM vw_korisnik_sazetak
ORDER BY neplaceno_prekrsaja DESC, zadnji_prekrsaj_datum DESC
LIMIT 10;

-- 2) Samo korisnici s "otvorenim" pritužbama:
SELECT korisnik_id, ime, prezime, otvoreno_prituzbi
FROM vw_korisnik_sazetak
WHERE otvoreno_prituzbi > 0
ORDER BY otvoreno_prituzbi DESC;

-- 3) Provjera za konkretnog korisnika:
SELECT * FROM vw_korisnik_sazetak WHERE korisnik_id = 3;
