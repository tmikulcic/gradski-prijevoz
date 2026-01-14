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