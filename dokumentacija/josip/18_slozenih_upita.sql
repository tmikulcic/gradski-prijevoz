-- ===============================================
-- 18 SMISLENIH SLOŽENIH UPITA ZA SUSTAV GRADSKOG PRIJEVOZA
-- Korištenje podupita i JOIN-ova
-- ===============================================
USE gradski_prijevoz;

-- ===============================================
-- UPIT 1: Korisnici s više prekršaja od prosjeka
-- Koristi podupit za izračun prosječnog broja prekršaja
-- ===============================================
SELECT
    k.id,
    CONCAT(k.ime, ' ', k.prezime) AS ime_prezime,
    k.email,
    kp.kategorija_naziv,
    COUNT(p.id) AS broj_prekrsaja,
    SUM(p.iznos_kazne) AS ukupna_kazna
FROM
    korisnici k
    INNER JOIN kategorija_putnik kp ON k.kategorija_id = kp.id
    LEFT JOIN prekrsaji p ON k.id = p.korisnik_id
GROUP BY
    k.id,
    k.ime,
    k.prezime,
    k.email,
    kp.kategorija_naziv
HAVING
    COUNT(p.id) > (
        SELECT AVG(broj_prekrsaja)
        FROM (
                SELECT COUNT(*) AS broj_prekrsaja
                FROM prekrsaji
                GROUP BY
                    korisnik_id
            ) AS prosjecni_prekrsaji
    )
ORDER BY broj_prekrsaja DESC;

-- ===============================================
-- UPIT 2: Vozila s troškovima održavanja iznad prosjeka
-- Koristi podupit i JOIN za usporedbu troškova
-- ===============================================
SELECT
    v.id,
    v.registarska_oznaka,
    v.tip_vozila,
    v.vrsta_goriva,
    COUNT(ov.id) AS broj_servisa,
    SUM(ov.trosak_servisa) AS ukupni_troskovi,
    ROUND(AVG(ov.trosak_servisa), 2) AS prosjecni_trosak
FROM
    vozila v
    LEFT JOIN odrzavanje_vozila ov ON v.id = ov.vozilo_id
GROUP BY
    v.id,
    v.registarska_oznaka,
    v.tip_vozila,
    v.vrsta_goriva
HAVING
    SUM(ov.trosak_servisa) > (
        SELECT AVG(ukupno)
        FROM (
                SELECT SUM(trosak_servisa) AS ukupno
                FROM odrzavanje_vozila
                GROUP BY
                    vozilo_id
            ) AS prosjek_troskova
    )
ORDER BY ukupni_troskovi DESC;

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

-- ===============================================
-- UPIT 6: Najpopularniji tipovi karata s usporedbom cijene
-- Koristi podupit za izračun razlike od prosjeka
-- ===============================================
SELECT
    tk.tip_naziv,
    tk.tip_kod,
    tk.osnovna_cijena,
    tk.trajanje_minute,
    COUNT(k.id) AS broj_prodanih,
    ROUND(SUM(k.placena_cijena), 2) AS ukupni_prihod,
    ROUND(
        tk.osnovna_cijena - (
            SELECT AVG(osnovna_cijena)
            FROM tip_karte
        ),
        2
    ) AS razlika_od_prosjeka,
    CASE
        WHEN tk.osnovna_cijena > (
            SELECT AVG(osnovna_cijena)
            FROM tip_karte
        ) THEN 'Iznad prosjeka'
        ELSE 'Ispod prosjeka'
    END AS kategorija_cijene
FROM tip_karte tk
    LEFT JOIN karta k ON tk.id = k.tip_karte_id
GROUP BY
    tk.id,
    tk.tip_naziv,
    tk.tip_kod,
    tk.osnovna_cijena,
    tk.trajanje_minute
ORDER BY broj_prodanih DESC;

-- ===============================================
-- UPIT 7: Zone s najviše stanica i njihovim linijama
-- Koristi podupite i JOIN-ove
-- ===============================================
SELECT
    z.zona_kod,
    z.zona_naziv,
    COUNT(DISTINCT s.id) AS broj_stanica,
    COUNT(DISTINCT ls.linija_id) AS broj_linija,
    GROUP_CONCAT(
        DISTINCT s.naziv
        ORDER BY s.naziv SEPARATOR ', '
    ) AS stanice,
    (
        SELECT COUNT(DISTINCT k.id)
        FROM korisnici k
            INNER JOIN karta ka ON k.id = ka.korisnik_id
        WHERE
            EXISTS (
                SELECT 1
                FROM stanice st
                WHERE
                    st.zona_id = z.id
            )
    ) AS potencijalni_putnici
FROM
    zone z
    LEFT JOIN stanice s ON z.id = s.zona_id
    LEFT JOIN linije_stanice ls ON s.id = ls.stanica_id
GROUP BY
    z.id,
    z.zona_kod,
    z.zona_naziv
HAVING
    COUNT(s.id) > 0
ORDER BY broj_stanica DESC;

-- ===============================================
-- UPIT 8: Korisnici koji nikad nisu dobili prekršaj
-- Koristi NOT EXISTS podupit
-- ===============================================
SELECT
    k.id,
    CONCAT(k.ime, ' ', k.prezime) AS ime_prezime,
    k.email,
    k.datum_rodenja,
    kp.kategorija_naziv,
    kp.postotak_popusta,
    COUNT(ka.id) AS broj_karata,
    COALESCE(SUM(ka.placena_cijena), 0) AS ukupno_potroseno
FROM
    korisnici k
    INNER JOIN kategorija_putnik kp ON k.kategorija_id = kp.id
    LEFT JOIN karta ka ON k.id = ka.korisnik_id
WHERE
    NOT EXISTS (
        SELECT 1
        FROM prekrsaji p
        WHERE
            p.korisnik_id = k.id
    )
GROUP BY
    k.id,
    k.ime,
    k.prezime,
    k.email,
    k.datum_rodenja,
    kp.kategorija_naziv,
    kp.postotak_popusta
ORDER BY broj_karata DESC;

-- ===============================================
-- UPIT 9: Vozila koja nisu bila na servisu dulje od 3 mjeseca
-- Koristi podupit s datumskom logikom
-- ===============================================
SELECT
    v.id,
    v.registarska_oznaka,
    v.tip_vozila,
    v.kapacitet_putnika,
    v.u_prometu,
    (
        SELECT MAX(datum_servisa)
        FROM odrzavanje_vozila
        WHERE
            vozilo_id = v.id
    ) AS zadnji_servis,
    DATEDIFF(
        CURDATE(),
        (
            SELECT MAX(datum_servisa)
            FROM odrzavanje_vozila
            WHERE
                vozilo_id = v.id
        )
    ) AS dana_od_servisa,
    (
        SELECT COUNT(*)
        FROM vozni_red
        WHERE
            vozilo_id = v.id
    ) AS broj_smjena_u_voznom_redu
FROM vozila v
WHERE
    DATEDIFF(
        CURDATE(),
        (
            SELECT COALESCE(
                    MAX(datum_servisa), '2020-01-01'
                )
            FROM odrzavanje_vozila
            WHERE
                vozilo_id = v.id
        )
    ) > 90
ORDER BY dana_od_servisa DESC;

-- ===============================================
-- UPIT 10: Usporedba tramvajskih i autobusnih linija
-- Koristi UNION i podupite za agregaciju
-- ===============================================
SELECT
    'Tramvajska' AS tip_linije,
    COUNT(*) AS broj_linija,
    ROUND(AVG(duljina_km), 2) AS prosjecna_duljina,
    (
        SELECT COUNT(DISTINCT vr.vozilo_id)
        FROM vozni_red vr
            INNER JOIN linije l2 ON vr.linija_id = l2.id
        WHERE
            l2.tip_linije = 'Tramvajska'
    ) AS broj_vozila,
    (
        SELECT SUM(v.kapacitet_putnika)
        FROM
            vozni_red vr
            INNER JOIN linije l2 ON vr.linija_id = l2.id
            INNER JOIN vozila v ON vr.vozilo_id = v.id
        WHERE
            l2.tip_linije = 'Tramvajska'
    ) AS ukupni_kapacitet
FROM linije
WHERE
    tip_linije = 'Tramvajska'
UNION ALL
SELECT
    'Autobusna' AS tip_linije,
    COUNT(*) AS broj_linija,
    ROUND(AVG(duljina_km), 2) AS prosjecna_duljina,
    (
        SELECT COUNT(DISTINCT vr.vozilo_id)
        FROM vozni_red vr
            INNER JOIN linije l2 ON vr.linija_id = l2.id
        WHERE
            l2.tip_linije = 'Autobusna'
    ) AS broj_vozila,
    (
        SELECT SUM(v.kapacitet_putnika)
        FROM
            vozni_red vr
            INNER JOIN linije l2 ON vr.linija_id = l2.id
            INNER JOIN vozila v ON vr.vozilo_id = v.id
        WHERE
            l2.tip_linije = 'Autobusna'
    ) AS ukupni_kapacitet
FROM linije
WHERE
    tip_linije = 'Autobusna';

-- ===============================================
-- UPIT 11: Top 5 korisnika po potrošnji s njihovim statusom
-- Koristi višestruke podupite i JOIN-ove
-- ===============================================
SELECT
    k.id,
    CONCAT(k.ime, ' ', k.prezime) AS ime_prezime,
    k.status_racuna,
    kp.kategorija_naziv,
    COUNT(ka.id) AS broj_karata,
    ROUND(SUM(ka.placena_cijena), 2) AS ukupna_potrosnja,
    (
        SELECT COUNT(*)
        FROM prekrsaji
        WHERE
            korisnik_id = k.id
    ) AS broj_prekrsaja,
    (
        SELECT COALESCE(SUM(iznos_kazne), 0)
        FROM prekrsaji
        WHERE
            korisnik_id = k.id
            AND status_placanja = 'Neplaćeno'
    ) AS neplacene_kazne,
    CASE
        WHEN (
            SELECT COUNT(*)
            FROM prekrsaji
            WHERE
                korisnik_id = k.id
        ) = 0 THEN 'Uzoran putnik'
        WHEN (
            SELECT COUNT(*)
            FROM prekrsaji
            WHERE
                korisnik_id = k.id
        ) <= 2 THEN 'Prihvatljiv'
        ELSE 'Problematičan'
    END AS ocjena_ponasanja
FROM
    korisnici k
    INNER JOIN kategorija_putnik kp ON k.kategorija_id = kp.id
    LEFT JOIN karta ka ON k.id = ka.korisnik_id
GROUP BY
    k.id,
    k.ime,
    k.prezime,
    k.status_racuna,
    kp.kategorija_naziv
ORDER BY ukupna_potrosnja DESC
LIMIT 5;

-- ===============================================
-- UPIT 12: Analiza rada kontrolora
-- Koristi JOIN i agregaciju s podupitima
-- ===============================================
SELECT
    z.zaposlenik_broj,
    CONCAT(z.ime, ' ', z.prezime) AS kontrolor,
    z.datum_zaposlenja,
    COUNT(p.id) AS broj_izdanih_kazni,
    ROUND(SUM(p.iznos_kazne), 2) AS ukupan_iznos_kazni,
    SUM(
        CASE
            WHEN p.status_placanja = 'Plaćeno' THEN 1
            ELSE 0
        END
    ) AS placenih,
    SUM(
        CASE
            WHEN p.status_placanja = 'Neplaćeno' THEN 1
            ELSE 0
        END
    ) AS neplacenih,
    ROUND(
        SUM(
            CASE
                WHEN p.status_placanja = 'Plaćeno' THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(p.id),
        2
    ) AS postotak_naplate,
    (
        SELECT AVG(broj_kazni)
        FROM (
                SELECT COUNT(*) AS broj_kazni
                FROM prekrsaji
                GROUP BY
                    zaposlenik_id
            ) AS prosjek
    ) AS prosjek_svih_kontrolora
FROM zaposlenik z
    LEFT JOIN prekrsaji p ON z.id = p.zaposlenik_id
WHERE
    z.naziv_uloge = 'Kontrolor'
GROUP BY
    z.id,
    z.zaposlenik_broj,
    z.ime,
    z.prezime,
    z.datum_zaposlenja
ORDER BY broj_izdanih_kazni DESC;

-- ===============================================
-- UPIT 13: Kalendari s najviše smjena i tipovi linija
-- Koristi JOIN preko više tablica
-- ===============================================
SELECT
    kal.kalendar_naziv,
    CONCAT(
        IF(kal.ponedjeljak, 'Pon ', ''),
        IF(kal.utorak, 'Uto ', ''),
        IF(kal.srijeda, 'Sri ', ''),
        IF(kal.cetvrtak, 'Čet ', ''),
        IF(kal.petak, 'Pet ', ''),
        IF(kal.subota, 'Sub ', ''),
        IF(kal.nedjelja, 'Ned', '')
    ) AS aktivni_dani,
    COUNT(vr.id) AS broj_smjena,
    COUNT(DISTINCT vr.linija_id) AS broj_linija,
    COUNT(DISTINCT vr.vozilo_id) AS broj_vozila,
    COUNT(DISTINCT vr.vozac_id) AS broj_vozaca,
    GROUP_CONCAT(
        DISTINCT l.tip_linije
        ORDER BY l.tip_linije SEPARATOR ', '
    ) AS tipovi_linija
FROM
    kalendari kal
    LEFT JOIN vozni_red vr ON kal.id = vr.kalendar_id
    LEFT JOIN linije l ON vr.linija_id = l.id
GROUP BY
    kal.id,
    kal.kalendar_naziv,
    kal.ponedjeljak,
    kal.utorak,
    kal.srijeda,
    kal.cetvrtak,
    kal.petak,
    kal.subota,
    kal.nedjelja
HAVING
    COUNT(vr.id) > 0
ORDER BY broj_smjena DESC;

-- ===============================================
-- UPIT 14: Mehaničari i njihova produktivnost
-- Koristi JOIN i složene podupite
-- ===============================================
SELECT
    z.zaposlenik_broj,
    CONCAT(z.ime, ' ', z.prezime) AS mehanicar,
    COUNT(ov.id) AS broj_servisa,
    COUNT(DISTINCT ov.vozilo_id) AS broj_razlicitih_vozila,
    ROUND(SUM(ov.trosak_servisa), 2) AS ukupni_troskovi_servisa,
    ROUND(AVG(ov.trosak_servisa), 2) AS prosjecni_trosak,
    GROUP_CONCAT(
        DISTINCT ov.vrsta_servisa
        ORDER BY ov.vrsta_servisa SEPARATOR ', '
    ) AS vrste_servisa,
    (
        SELECT COUNT(*)
        FROM odrzavanje_vozila
        WHERE
            vrsta_servisa = 'Popravak kvar'
            AND zaposlenik_id = z.id
    ) AS broj_popravaka_kvara,
    (
        SELECT ROUND(SUM(trosak_servisa), 2)
        FROM odrzavanje_vozila
        WHERE
            vrsta_servisa = 'Redovni'
            AND zaposlenik_id = z.id
    ) AS troskovi_redovnih
FROM
    zaposlenik z
    INNER JOIN odrzavanje_vozila ov ON z.id = ov.zaposlenik_id
WHERE
    z.naziv_uloge = 'Mehaničar'
GROUP BY
    z.id,
    z.zaposlenik_broj,
    z.ime,
    z.prezime
ORDER BY broj_servisa DESC;

-- ===============================================
-- UPIT 15: Korisnici s aktivnim mjesečnim kartama
-- Koristi podupit i datumsku logiku
-- ===============================================
SELECT
    k.id,
    CONCAT(k.ime, ' ', k.prezime) AS ime_prezime,
    k.email,
    kp.kategorija_naziv,
    kp.postotak_popusta,
    ka.karta_kod,
    tk.tip_naziv,
    ka.datum_kupnje,
    ka.vrijedi_do,
    ka.placena_cijena,
    tk.osnovna_cijena,
    ROUND(
        (
            1 - ka.placena_cijena / tk.osnovna_cijena
        ) * 100,
        2
    ) AS ostvareni_popust_posto,
    DATEDIFF(ka.vrijedi_do, CURDATE()) AS preostalo_dana
FROM
    korisnici k
    INNER JOIN kategorija_putnik kp ON k.kategorija_id = kp.id
    INNER JOIN karta ka ON k.id = ka.korisnik_id
    INNER JOIN tip_karte tk ON ka.tip_karte_id = tk.id
WHERE
    tk.trajanje_minute >= 43200 -- Mjesečne i godišnje karte
    AND ka.vrijedi_do > CURDATE()
ORDER BY ka.vrijedi_do ASC;

-- ===============================================
-- UPIT 16: Stanice koje povezuju najviše linija
-- Koristi JOIN i podupite za rang
-- ===============================================
SELECT
    s.id,
    s.naziv AS naziv_stanice,
    z.zona_naziv,
    COUNT(DISTINCT ls.linija_id) AS broj_linija,
    GROUP_CONCAT(
        DISTINCT l.oznaka
        ORDER BY l.oznaka SEPARATOR ', '
    ) AS linije,
    GROUP_CONCAT(
        DISTINCT l.tip_linije
        ORDER BY l.tip_linije SEPARATOR ', '
    ) AS tipovi_prijevoza,
    (
        SELECT COUNT(*)
        FROM linije_stanice ls2
            INNER JOIN linije l2 ON ls2.linija_id = l2.id
        WHERE
            ls2.stanica_id = s.id
            AND l2.tip_linije = 'Tramvajska'
    ) AS tramvajskih_linija,
    (
        SELECT COUNT(*)
        FROM linije_stanice ls2
            INNER JOIN linije l2 ON ls2.linija_id = l2.id
        WHERE
            ls2.stanica_id = s.id
            AND l2.tip_linije = 'Autobusna'
    ) AS autobusnih_linija
FROM
    stanice s
    INNER JOIN zone z ON s.zona_id = z.id
    LEFT JOIN linije_stanice ls ON s.id = ls.stanica_id
    LEFT JOIN linije l ON ls.linija_id = l.id
GROUP BY
    s.id,
    s.naziv,
    z.zona_naziv
HAVING
    COUNT(DISTINCT ls.linija_id) > 0
ORDER BY broj_linija DESC
LIMIT 10;

-- ===============================================
-- UPIT 17: Analiza prihoda po mjesecima
-- Koristi grupiranje po datumu i podupite
-- ===============================================
SELECT
    mjesec_grupa.mjesec,
    mjesec_grupa.broj_prodanih_karata,
    mjesec_grupa.broj_razlicitih_kupaca,
    mjesec_grupa.ukupni_prihod,
    mjesec_grupa.prosjecna_cijena,
    (
        SELECT tk.tip_naziv
        FROM karta k2
            INNER JOIN tip_karte tk ON k2.tip_karte_id = tk.id
        WHERE
            DATE_FORMAT(k2.datum_kupnje, '%Y-%m') = mjesec_grupa.mjesec
        GROUP BY
            tk.tip_naziv
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS najpopularniji_tip,
    (
        SELECT COUNT(*)
        FROM prekrsaji p
        WHERE
            DATE_FORMAT(p.datum_prekrsaja, '%Y-%m') = mjesec_grupa.mjesec
    ) AS broj_prekrsaja_u_mjesecu
FROM (
        SELECT
            DATE_FORMAT(ka.datum_kupnje, '%Y-%m') AS mjesec, COUNT(ka.id) AS broj_prodanih_karata, COUNT(DISTINCT ka.korisnik_id) AS broj_razlicitih_kupaca, ROUND(SUM(ka.placena_cijena), 2) AS ukupni_prihod, ROUND(AVG(ka.placena_cijena), 2) AS prosjecna_cijena
        FROM karta ka
        GROUP BY
            DATE_FORMAT(ka.datum_kupnje, '%Y-%m')
    ) AS mjesec_grupa
ORDER BY mjesec_grupa.mjesec DESC;

-- ===============================================
-- UPIT 18: Kompleksna analiza voznog reda s rangiranjem
-- Koristi višestruke JOIN-ove i podupite
-- ===============================================
SELECT 
    l.oznaka AS broj_linije,
    l.naziv AS naziv_linije,
    l.tip_linije,
    l.duljina_km,
    vr.vrijeme_polaska,
    CONCAT(z.ime, ' ', z.prezime) AS vozac,
    v.registarska_oznaka,
    v.tip_vozila,
    v.kapacitet_putnika,
    kal.kalendar_naziv,
    (
        SELECT COUNT(*)
        FROM linije_stanice
        WHERE
            linija_id = l.id
    ) AS broj_stanica,
    (
        SELECT s.naziv
        FROM linije_stanice ls
            INNER JOIN stanice s ON ls.stanica_id = s.id
        WHERE
            ls.linija_id = l.id
        ORDER BY ls.redoslijed ASC
        LIMIT 1
    ) AS polazna_stanica,
    (
        SELECT s.naziv
        FROM linije_stanice ls
            INNER JOIN stanice s ON ls.stanica_id = s.id
        WHERE
            ls.linija_id = l.id
        ORDER BY ls.redoslijed DESC
        LIMIT 1
    ) AS zavrsna_stanica,
    (
        SELECT MAX(ov.datum_servisa)
        FROM odrzavanje_vozila ov
        WHERE
            ov.vozilo_id = v.id
    ) AS zadnji_servis_vozila,
    CASE
        WHEN TIME(vr.vrijeme_polaska) BETWEEN '05:00:00' AND '09:00:00'  THEN 'Jutarnja špica'
        WHEN TIME(vr.vrijeme_polaska) BETWEEN '09:00:00' AND '15:00:00'  THEN 'Sredina dana'
        WHEN TIME(vr.vrijeme_polaska) BETWEEN '15:00:00' AND '19:00:00'  THEN 'Popodnevna špica'
        ELSE 'Večernja/noćna'
    END AS vrijeme_smjene
FROM
    vozni_red vr
    INNER JOIN linije l ON vr.linija_id = l.id
    INNER JOIN vozila v ON vr.vozilo_id = v.id
    INNER JOIN zaposlenik z ON vr.vozac_id = z.id
    INNER JOIN kalendari kal ON vr.kalendar_id = kal.id
ORDER BY l.oznaka, vr.vrijeme_polaska;

-- ===============================================
-- KRAJ SKRIPTE S 18 SLOŽENIH UPITA
-- ===============================================