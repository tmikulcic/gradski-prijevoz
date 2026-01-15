-- ===============================================
-- UPIT 3: Linije s najvećim kapacitetom vozila u voznom redu
-- Koristi JOIN preko više tablica i podupit za rang
-- ===============================================
SELECT
    l.oznaka AS broj_linije,
    l.naziv AS naziv_linije,
    l.tip_linije,
    l.duljina_km,
    COUNT(DISTINCT vr.vozilo_id) AS broj_vozila,
    SUM(v.kapacitet_putnika) AS ukupni_kapacitet,
    (
        SELECT zona_naziv
        FROM zone
        WHERE
            id = (
                SELECT zona_id
                FROM stanice
                WHERE
                    id = (
                        SELECT stanica_id
                        FROM linije_stanice
                        WHERE
                            linija_id = l.id
                        ORDER BY redoslijed
                        LIMIT 1
                    )
            )
    ) AS pocetna_zona
FROM
    linije l
    INNER JOIN vozni_red vr ON l.id = vr.linija_id
    INNER JOIN vozila v ON vr.vozilo_id = v.id
GROUP BY
    l.id,
    l.oznaka,
    l.naziv,
    l.tip_linije,
    l.duljina_km
ORDER BY ukupni_kapacitet DESC
LIMIT 10;

-- ===============================================
-- UPIT 4: Zaposlenici vozači s najviše smjena i njihove linije
-- Koristi višestruke JOIN-ove i agregaciju
-- ===============================================
SELECT
    z.zaposlenik_broj,
    CONCAT(z.ime, ' ', z.prezime) AS vozac,
    z.datum_zaposlenja,
    DATEDIFF(CURDATE(), z.datum_zaposlenja) AS dana_radnog_staza,
    COUNT(vr.id) AS broj_smjena,
    COUNT(DISTINCT vr.linija_id) AS broj_razlicitih_linija,
    GROUP_CONCAT(
        DISTINCT l.oznaka
        ORDER BY l.oznaka SEPARATOR ', '
    ) AS linije
FROM
    zaposlenik z
    INNER JOIN vozni_red vr ON z.id = vr.vozac_id
    INNER JOIN linije l ON vr.linija_id = l.id
WHERE
    z.naziv_uloge = 'Vozač'
GROUP BY
    z.id,
    z.zaposlenik_broj,
    z.ime,
    z.prezime,
    z.datum_zaposlenja
ORDER BY broj_smjena DESC;

-- ===============================================
-- UPIT 5: Prihod od karata po kategoriji putnika
-- Koristi JOIN preko više tablica i agregaciju
-- ===============================================
SELECT
    kp.kategorija_naziv,
    kp.postotak_popusta,
    COUNT(DISTINCT k.id) AS broj_korisnika,
    COUNT(ka.id) AS broj_kupljenih_karata,
    ROUND(SUM(ka.placena_cijena), 2) AS ukupni_prihod,
    ROUND(AVG(ka.placena_cijena), 2) AS prosjecna_cijena_karte,
    (
        SELECT COUNT(*)
        FROM prekrsaji p
            INNER JOIN korisnici kor ON p.korisnik_id = kor.id
        WHERE
            kor.kategorija_id = kp.id
    ) AS broj_prekrsaja
FROM
    kategorija_putnik kp
    LEFT JOIN korisnici k ON kp.id = k.kategorija_id
    LEFT JOIN karta ka ON k.id = ka.korisnik_id
GROUP BY
    kp.id,
    kp.kategorija_naziv,
    kp.postotak_popusta
ORDER BY ukupni_prihod DESC;

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
-- PROCEDURA: sp_podmiri_kazne_korisnika
-- Opis:
--   - Označi SVE neplaćene prekršaje korisnika kao "Plaćeno"
--   - Ako nakon toga korisnik nema više neplaćenih, a bio je suspendiran -> reaktiviraj ga
--   - Vraća broj ažuriranih prekršaja i poruku
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