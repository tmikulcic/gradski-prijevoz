-- ============================================================
-- BAZA: gradski_prijevoz
-- 6 SMISLENIH POGLEDA (VIEWS)
-- ============================================================

USE gradski_prijevoz;

-- ============================================================
-- VIEW 1: vw_korisnici_pregled
-- Opis: Kompletan pregled korisnika s kategorijom, popustom,
--       brojem kupljenih karata i neplaćenih prekršaja
-- Korištenje: Dashboard korisnika, korisnička služba
-- ============================================================
DROP VIEW IF EXISTS vw_korisnici_pregled;

CREATE VIEW vw_korisnici_pregled AS
SELECT
    k.id AS korisnik_id,
    CONCAT(k.ime, ' ', k.prezime) AS ime_prezime,
    k.email,
    k.datum_rodenja,
    TIMESTAMPDIFF(
        YEAR,
        k.datum_rodenja,
        CURDATE()
    ) AS dob,
    k.status_racuna,
    kp.kategorija_naziv,
    kp.postotak_popusta,
    (
        SELECT COUNT(*)
        FROM karta
        WHERE
            korisnik_id = k.id
    ) AS broj_karata,
    (
        SELECT COUNT(*)
        FROM karta
        WHERE
            korisnik_id = k.id
            AND vrijedi_do > NOW()
    ) AS aktivne_karte,
    (
        SELECT COUNT(*)
        FROM prekrsaji
        WHERE
            korisnik_id = k.id
            AND status_placanja = 'Neplaćeno'
    ) AS neplaceni_prekrsaji,
    (
        SELECT COALESCE(SUM(iznos_kazne), 0)
        FROM prekrsaji
        WHERE
            korisnik_id = k.id
            AND status_placanja = 'Neplaćeno'
    ) AS ukupno_dugovanje,
    (
        SELECT COUNT(*)
        FROM prituzbe
        WHERE
            korisnik_id = k.id
    ) AS broj_prituzbi
FROM
    korisnici k
    LEFT JOIN kategorija_putnik kp ON k.kategorija_id = kp.id;

-- ============================================================
-- VIEW 2: vw_vozila_status
-- Opis: Pregled svih vozila s trenutnim statusom, zadnjim servisom
--       i ukupnim troškovima održavanja
-- Korištenje: Upravljanje voznim parkom, planiranje servisa
-- ============================================================
DROP VIEW IF EXISTS vw_vozila_status;

CREATE VIEW vw_vozila_status AS
SELECT
    v.id AS vozilo_id,
    v.registarska_oznaka,
    v.tip_vozila,
    v.vrsta_goriva,
    v.kapacitet_putnika,
    CASE
        WHEN v.u_prometu = 1 THEN 'U prometu'
        ELSE 'Van prometa'
    END AS status,
    (
        SELECT MAX(datum_servisa)
        FROM odrzavanje_vozila
        WHERE
            vozilo_id = v.id
    ) AS zadnji_servis,
    (
        SELECT vrsta_servisa
        FROM odrzavanje_vozila
        WHERE
            vozilo_id = v.id
        ORDER BY datum_servisa DESC
        LIMIT 1
    ) AS zadnja_vrsta_servisa,
    (
        SELECT COUNT(*)
        FROM odrzavanje_vozila
        WHERE
            vozilo_id = v.id
    ) AS ukupno_servisa,
    (
        SELECT COALESCE(SUM(trosak_servisa), 0)
        FROM odrzavanje_vozila
        WHERE
            vozilo_id = v.id
    ) AS ukupni_troskovi_servisa,
    (
        SELECT COUNT(*)
        FROM vozni_red
        WHERE
            vozilo_id = v.id
    ) AS broj_linija_rasporedeno,
    DATEDIFF(
        CURDATE(),
        (
            SELECT MAX(datum_servisa)
            FROM odrzavanje_vozila
            WHERE
                vozilo_id = v.id
        )
    ) AS dana_od_servisa
FROM vozila v;

-- ============================================================
-- VIEW 3: vw_linije_sa_stanicama
-- Opis: Pregled svih linija s brojem stanica, početnom i
--       završnom stanicom, te brojem polazaka
-- Korištenje: Planiranje mreže, informacije putnicima
-- ============================================================
DROP VIEW IF EXISTS vw_linije_sa_stanicama;

CREATE VIEW vw_linije_sa_stanicama AS
SELECT
    l.id AS linija_id,
    l.oznaka,
    l.naziv AS naziv_linije,
    l.tip_linije,
    l.duljina_km,
    (
        SELECT COUNT(*)
        FROM linije_stanice
        WHERE
            linija_id = l.id
    ) AS broj_stanica,
    (
        SELECT s.naziv
        FROM stanice s
            JOIN linije_stanice ls ON s.id = ls.stanica_id
        WHERE
            ls.linija_id = l.id
        ORDER BY ls.redoslijed ASC
        LIMIT 1
    ) AS pocetna_stanica,
    (
        SELECT s.naziv
        FROM stanice s
            JOIN linije_stanice ls ON s.id = ls.stanica_id
        WHERE
            ls.linija_id = l.id
        ORDER BY ls.redoslijed DESC
        LIMIT 1
    ) AS zavrsna_stanica,
    (
        SELECT COUNT(*)
        FROM vozni_red
        WHERE
            linija_id = l.id
    ) AS broj_polazaka,
    (
        SELECT COUNT(DISTINCT vozilo_id)
        FROM vozni_red
        WHERE
            linija_id = l.id
    ) AS broj_vozila,
    (
        SELECT COUNT(*)
        FROM prituzbe
        WHERE
            linija_id = l.id
    ) AS broj_prituzbi
FROM linije l;

-- ============================================================
-- VIEW 4: vw_dnevna_statistika
-- Opis: Detaljna dnevna statistika poslovanja s prihodima,
--       troškovima i neto rezultatom
-- Korištenje: Dnevni izvještaji, financijska analiza
-- ============================================================
DROP VIEW IF EXISTS vw_dnevna_statistika;

CREATE VIEW vw_dnevna_statistika AS
SELECT
    s.datum,
    DAYNAME(s.datum) AS dan_u_tjednu,
    s.ukupno_karata_prodano,
    s.ukupan_prihod AS prihod_od_karata,
    s.ukupno_prekrsaja,
    s.ukupno_kazni AS prihod_od_kazni,
    s.broj_servisa,
    s.troskovi_servisa,
    s.broj_prituzbi,
    (
        s.ukupan_prihod + s.ukupno_kazni
    ) AS ukupni_prihodi,
    s.troskovi_servisa AS ukupni_troskovi,
    (
        s.ukupan_prihod + s.ukupno_kazni - s.troskovi_servisa
    ) AS neto_rezultat,
    CASE
        WHEN (
            s.ukupan_prihod + s.ukupno_kazni - s.troskovi_servisa
        ) > 0 THEN 'Pozitivan'
        WHEN (
            s.ukupan_prihod + s.ukupno_kazni - s.troskovi_servisa
        ) < 0 THEN 'Negativan'
        ELSE 'Neutralan'
    END AS status_dana
FROM statistika_sustava s
ORDER BY s.datum DESC;

-- ============================================================
-- VIEW 5: vw_vozni_red_detalji
-- Opis: Kompletan vozni red s detaljima o liniji, vozilu,
--       vozaču i kalendaru
-- Korištenje: Raspored vozača, planiranje prometa, info putnicima
-- ============================================================
DROP VIEW IF EXISTS vw_vozni_red_detalji;

CREATE VIEW vw_vozni_red_detalji AS
SELECT
    vr.id AS vozni_red_id,
    l.oznaka AS linija_oznaka,
    l.naziv AS linija_naziv,
    l.tip_linije,
    v.registarska_oznaka,
    v.tip_vozila,
    v.kapacitet_putnika,
    CONCAT(z.ime, ' ', z.prezime) AS vozac,
    z.zaposlenik_broj,
    vr.vrijeme_polaska,
    kal.kalendar_naziv,
    CASE
        WHEN kal.ponedjeljak = 1 THEN 'Da'
        ELSE 'Ne'
    END AS ponedjeljak,
    CASE
        WHEN kal.utorak = 1 THEN 'Da'
        ELSE 'Ne'
    END AS utorak,
    CASE
        WHEN kal.srijeda = 1 THEN 'Da'
        ELSE 'Ne'
    END AS srijeda,
    CASE
        WHEN kal.cetvrtak = 1 THEN 'Da'
        ELSE 'Ne'
    END AS cetvrtak,
    CASE
        WHEN kal.petak = 1 THEN 'Da'
        ELSE 'Ne'
    END AS petak,
    CASE
        WHEN kal.subota = 1 THEN 'Da'
        ELSE 'Ne'
    END AS subota,
    CASE
        WHEN kal.nedjelja = 1 THEN 'Da'
        ELSE 'Ne'
    END AS nedjelja,
    CASE
        WHEN v.u_prometu = 1 THEN 'Aktivno'
        ELSE 'Neaktivno (vozilo van prometa)'
    END AS status_rasporeda
FROM
    vozni_red vr
    JOIN linije l ON vr.linija_id = l.id
    JOIN vozila v ON vr.vozilo_id = v.id
    JOIN zaposlenik z ON vr.vozac_id = z.id
    JOIN kalendari kal ON vr.kalendar_id = kal.id
ORDER BY l.oznaka, vr.vrijeme_polaska;

-- ============================================================
-- VIEW 6: vw_neplacene_kazne_pregled
-- Opis: Pregled svih neplaćenih kazni s detaljima o korisniku
--       i zaposleniku koji je evidentirao prekršaj
-- Korištenje: Naplata dugovanja, praćenje prekršaja
-- ============================================================
DROP VIEW IF EXISTS vw_neplacene_kazne_pregled;

CREATE VIEW vw_neplacene_kazne_pregled AS
SELECT
    p.id AS prekrsaj_id,
    p.datum_prekrsaja,
    p.iznos_kazne,
    p.status_placanja,
    p.napomena,
    k.id AS korisnik_id,
    CONCAT(k.ime, ' ', k.prezime) AS korisnik_ime,
    k.email AS korisnik_email,
    k.status_racuna AS status_korisnika,
    CONCAT(z.ime, ' ', z.prezime) AS kontrolor,
    z.zaposlenik_broj AS kontrolor_broj,
    DATEDIFF(
        CURDATE(),
        DATE(p.datum_prekrsaja)
    ) AS dana_neplaceno,
    CASE
        WHEN DATEDIFF(
            CURDATE(),
            DATE(p.datum_prekrsaja)
        ) > 90 THEN 'Kritično (>90 dana)'
        WHEN DATEDIFF(
            CURDATE(),
            DATE(p.datum_prekrsaja)
        ) > 30 THEN 'Upozorenje (>30 dana)'
        ELSE 'Novo (<30 dana)'
    END AS prioritet_naplate,
    (
        SELECT COUNT(*)
        FROM prekrsaji
        WHERE
            korisnik_id = k.id
            AND status_placanja = 'Neplaćeno'
    ) AS ukupno_neplacenih_korisnik,
    (
        SELECT SUM(iznos_kazne)
        FROM prekrsaji
        WHERE
            korisnik_id = k.id
            AND status_placanja = 'Neplaćeno'
    ) AS ukupno_dugovanje_korisnik
FROM
    prekrsaji p
    JOIN korisnici k ON p.korisnik_id = k.id
    JOIN zaposlenik z ON p.zaposlenik_id = z.id
WHERE
    p.status_placanja = 'Neplaćeno'
ORDER BY dana_neplaceno DESC, p.iznos_kazne DESC;

-- ============================================================
-- SAŽETAK POGLEDA:
-- ============================================================
-- 1. vw_korisnici_pregled     - Dashboard korisnika (status, popust, dugovanja)
-- 2. vw_vozila_status         - Upravljanje voznim parkom (servisi, troškovi)
-- 3. vw_linije_sa_stanicama   - Mreža linija (stanice, polasci, pritužbe)
-- 4. vw_dnevna_statistika     - Financijska analiza (prihodi, troškovi, neto)
-- 5. vw_vozni_red_detalji     - Raspored prometa (linije, vozila, vozači)
-- 6. vw_neplacene_kazne_pregled - Naplata dugovanja (prioriteti, starost)
-- ============================================================

-- ============================================================
-- PRIMJERI KORIŠTENJA:
-- ============================================================

-- Svi suspendirani korisnici s dugovanjem
-- SELECT * FROM vw_korisnici_pregled WHERE status_racuna = 'Suspendiran';

-- Vozila koja nisu bila na servisu više od 180 dana
-- SELECT * FROM vw_vozila_status WHERE dana_od_servisa > 180 OR dana_od_servisa IS NULL;

-- Linije s najviše pritužbi
-- SELECT * FROM vw_linije_sa_stanicama ORDER BY broj_prituzbi DESC LIMIT 5;

-- Ukupna statistika za ovaj mjesec
-- SELECT SUM(prihod_od_karata) AS prihod, SUM(troskovi_servisa) AS troskovi, SUM(neto_rezultat) AS neto
-- FROM vw_dnevna_statistika
-- WHERE MONTH(datum) = MONTH(CURDATE()) AND YEAR(datum) = YEAR(CURDATE());

-- Vozni red za tramvajske linije
-- SELECT * FROM vw_vozni_red_detalji WHERE tip_linije = 'Tramvajska';

-- Kritične neplaćene kazne
-- SELECT * FROM vw_neplacene_kazne_pregled WHERE prioritet_naplate = 'Kritično (>90 dana)';