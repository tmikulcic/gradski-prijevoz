-- ============================================================
-- SKRIPTA ZA TESTIRANJE
-- Procedura 11 i 12, Trigger 6, Funkcija 6, View 6
-- Baza: gradski_prijevoz
-- ============================================================

USE gradski_prijevoz;


-- 1. TESTIRANJE PROCEDURE 11: KreirajVozniRed

-- Test 1.1: Uspješno kreiranje voznog reda

CALL KreirajVozniRed ( 1, 1, 1, 1, '06:00:00', @id, @poruka );

SELECT @id AS vozni_red_id, @poruka AS poruka;

-- Test 1.2: Pokušaj s nepostojećom linijom

CALL KreirajVozniRed ( 9999, 1, 1, 1, '07:00:00', @id, @poruka );

SELECT @id AS vozni_red_id, @poruka AS poruka;

-- Test 1.3: Pokušaj s nepostojećim vozilom

CALL KreirajVozniRed ( 1, 9999, 1, 1, '07:00:00', @id, @poruka );

SELECT @id AS vozni_red_id, @poruka AS poruka;

-- Test 1.4: Pokušaj s nepostojećim vozačem

CALL KreirajVozniRed ( 1, 1, 9999, 1, '07:00:00', @id, @poruka );

SELECT @id AS vozni_red_id, @poruka AS poruka;

-- Test 1.5: Pokušaj s nepostojećim kalendarom

CALL KreirajVozniRed ( 1, 1, 1, 9999, '07:00:00', @id, @poruka );

SELECT @id AS vozni_red_id, @poruka AS poruka;

-- Test 1.6: Konflikt vozila (±30 minuta od prethodnog unosa u 06:00)

CALL KreirajVozniRed ( 2, 1, 2, 1, '06:15:00', @id, @poruka );

SELECT @id AS vozni_red_id, @poruka AS poruka;

-- Test 1.7: Konflikt vozača (±30 minuta)

CALL KreirajVozniRed ( 2, 2, 1, 1, '06:20:00', @id, @poruka );

SELECT @id AS vozni_red_id, @poruka AS poruka;

-- Provjera audit loga

SELECT *
FROM audit_log
WHERE
    tablica_naziv = 'vozni_red'
ORDER BY vrijeme_promjene DESC
LIMIT 5;


-- 2. TESTIRANJE PROCEDURE 12: ArhivirajStareKarte

-- Test 2.1: Provjera broja karata prije arhiviranja

SELECT
    COUNT(*) AS ukupno_karata,
    SUM(
        CASE
            WHEN vrijedi_do < DATE_SUB(CURDATE(), INTERVAL 365 DAY) THEN 1
            ELSE 0
        END
    ) AS starije_od_365_dana
FROM karta;

-- Test 2.2: Arhiviranje karata starijih od 365 dana

CALL ArhivirajStareKarte ( 365, @obrisano, @vrijednost, @poruka );

SELECT
    @obrisano AS broj_obrisanih,
    @vrijednost AS ukupna_vrijednost,
    @poruka AS poruka;

-- Test 2.3: Arhiviranje s 0 dana (sve istekle karte)

CALL ArhivirajStareKarte ( 0, @obrisano, @vrijednost, @poruka );

SELECT
    @obrisano AS broj_obrisanih,
    @vrijednost AS ukupna_vrijednost,
    @poruka AS poruka;

-- Test 2.4: Pokušaj arhiviranja kad nema karata za brisanje

CALL ArhivirajStareKarte ( 365, @obrisano, @vrijednost, @poruka );

SELECT
    @obrisano AS broj_obrisanih,
    @vrijednost AS ukupna_vrijednost,
    @poruka AS poruka;

-- Provjera audit loga za arhiviranje

SELECT *
FROM audit_log
WHERE
    tablica_naziv = 'karta'
    AND operacija = 'DELETE'
ORDER BY vrijeme_promjene DESC
LIMIT 5;

-- 3. TESTIRANJE TRIGGERA 6: trg_vozni_red_before_insert

-- NAPOMENA: Trigger se aktivira automatski pri INSERT-u.
-- Potrebno je imati vozilo van prometa i nekompatibilno vozilo za testiranje.

-- Priprema: Dohvati ID vozila koje je van prometa

SELECT
    id,
    registarska_oznaka,
    tip_vozila,
    u_prometu
FROM vozila
WHERE
    u_prometu = 0
LIMIT 3;

-- Priprema: Dohvati tramvajsku liniju i autobus za test nekompatibilnosti

SELECT l.id AS linija_id, l.oznaka, l.tip_linije
FROM linije l
LIMIT 5;

SELECT v.id AS vozilo_id, v.registarska_oznaka, v.tip_vozila, v.u_prometu
FROM vozila v
WHERE
    v.u_prometu = 1
LIMIT 5;

-- Test 3.1: Uspješan unos (ako postoji kompatibilno vozilo)
-- NAPOMENA: Ovaj test može uspjeti ili ne ovisno o podacima u bazi
SELECT 'Test 3.1: Pokušaj uspješnog unosa putem direktnog INSERT-a' AS opis_testa;
-- INSERT INTO vozni_red (linija_id, vozilo_id, vozac_id, kalendar_id, vrijeme_polaska)
-- VALUES (1, 1, 1, 1, '14:00:00');
-- Zakomentirano jer može izazvati grešku ovisno o stanju baze

-- Test 3.2: Unos s vozilom van prometa (očekuje se SIGNAL error)
SELECT 'Test 3.2: Ručni test - pokušati INSERT s vozilom koje ima u_prometu=0' AS opis_testa;

SELECT 'Primjer: INSERT INTO vozni_red (...) VALUES (linija_id, vozilo_van_prometa_id, ...)' AS uputa;

SELECT 'Očekivani rezultat: ERROR 1644 (45000): Greška: Vozilo nije u prometu' AS ocekivano;

-- Test 3.3: Unos s nekompatibilnim tipom vozila
SELECT 'Test 3.3: Ručni test - pokušati INSERT autobusa na tramvajsku liniju' AS opis_testa;

SELECT 'Očekivani rezultat: ERROR 1644 (45000): Greška: Tip vozila nije kompatibilan' AS ocekivano;

-- ============================================================
-- 4. TESTIRANJE FUNKCIJE 6: fn_izracunaj_staz_zaposlenika
-- ============================================================

-- Test 4.1: Dohvat staža jednog zaposlenika

SELECT fn_izracunaj_staz_zaposlenika (1) AS radni_staz;

-- Test 4.2: Staž svih zaposlenika

SELECT
    z.id,
    CONCAT(z.ime, ' ', z.prezime) AS ime_prezime,
    z.naziv_uloge,
    z.datum_zaposlenja,
    fn_izracunaj_staz_zaposlenika (z.id) AS radni_staz
FROM zaposlenik z
ORDER BY z.datum_zaposlenja ASC
LIMIT 10;

-- Test 4.3: Nepostojeći zaposlenik (očekuje se NULL)

SELECT fn_izracunaj_staz_zaposlenika (9999) AS radni_staz;

-- Test 4.4: Zaposlenici s više od 5 godina staža

SELECT
    z.id,
    CONCAT(z.ime, ' ', z.prezime) AS ime_prezime,
    fn_izracunaj_staz_zaposlenika (z.id) AS radni_staz
FROM zaposlenik z
WHERE
    TIMESTAMPDIFF(
        YEAR,
        z.datum_zaposlenja,
        CURDATE()
    ) >= 5
ORDER BY z.datum_zaposlenja ASC;

-- Test 4.5: Prosječni staž svih zaposlenika

SELECT
    z.naziv_uloge,
    COUNT(*) AS broj_zaposlenika,
    ROUND(
        AVG(
            DATEDIFF(CURDATE(), z.datum_zaposlenja)
        ),
        0
    ) AS prosjecni_staz_dana,
    ROUND(
        AVG(
            DATEDIFF(CURDATE(), z.datum_zaposlenja)
        ) / 365,
        1
    ) AS prosjecni_staz_godina
FROM zaposlenik z
GROUP BY
    z.naziv_uloge
ORDER BY prosjecni_staz_dana DESC;

-- ============================================================
-- 5. TESTIRANJE VIEW-a 6: vw_neplacene_kazne_pregled
-- ============================================================

-- Test 5.1: Dohvat svih neplaćenih kazni

SELECT * FROM vw_neplacene_kazne_pregled LIMIT 10;

-- Test 5.2: Samo kritične kazne (starije od 90 dana)

SELECT
    korisnik_ime,
    korisnik_email,
    iznos_kazne,
    dana_neplaceno,
    prioritet_naplate
FROM vw_neplacene_kazne_pregled
WHERE
    prioritet_naplate = 'Kritično (>90 dana)'
LIMIT 10;

-- Test 5.3: Korisnici s više od 3 neplaćene kazne
SELECT 'Test 5.3: Korisnici s 3+ neplaćene kazne' AS opis_testa;

SELECT DISTINCT
    korisnik_id,
    korisnik_ime,
    korisnik_email,
    ukupno_neplacenih_korisnik,
    ukupno_dugovanje_korisnik
FROM vw_neplacene_kazne_pregled
WHERE
    ukupno_neplacenih_korisnik >= 3
ORDER BY ukupno_dugovanje_korisnik DESC
LIMIT 10;

-- Test 5.4: Ukupna statistika neplaćenih kazni po prioritetu

SELECT
    prioritet_naplate,
    COUNT(*) AS broj_kazni,
    SUM(iznos_kazne) AS ukupan_iznos,
    ROUND(AVG(iznos_kazne), 2) AS prosjecni_iznos
FROM vw_neplacene_kazne_pregled
GROUP BY
    prioritet_naplate
ORDER BY
    CASE prioritet_naplate
        WHEN 'Kritično (>90 dana)' THEN 1
        WHEN 'Upozorenje (>30 dana)' THEN 2
        ELSE 3
    END;

-- Test 5.5: Lista za email opomene (kazne starije od 30 dana)
SELECT 'Test 5.5: Lista za email opomene' AS opis_testa;

SELECT
    korisnik_email,
    korisnik_ime,
    iznos_kazne,
    dana_neplaceno,
    napomena
FROM vw_neplacene_kazne_pregled
WHERE
    dana_neplaceno >= 30
    AND korisnik_email IS NOT NULL
ORDER BY korisnik_email, dana_neplaceno DESC
LIMIT 10;

-- Test 5.6: Produktivnost kontrolora
SELECT 'Test 5.6: Produktivnost kontrolora' AS opis_testa;

SELECT
    kontrolor,
    kontrolor_broj,
    COUNT(*) AS broj_evidentiranih_prekrsaja,
    SUM(iznos_kazne) AS ukupna_vrijednost
FROM vw_neplacene_kazne_pregled
GROUP BY
    kontrolor,
    kontrolor_broj
ORDER BY broj_evidentiranih_prekrsaja DESC
LIMIT 10;

-- Test 5.7: Ukupno dugovanje u sustavu
SELECT 'Test 5.7: Sažetak ukupnog dugovanja' AS opis_testa;

SELECT
    COUNT(*) AS ukupno_neplacenih_kazni,
    SUM(iznos_kazne) AS ukupno_dugovanje_eur,
    COUNT(DISTINCT korisnik_id) AS broj_duznika,
    ROUND(AVG(dana_neplaceno), 0) AS prosjecna_starost_dana
FROM vw_neplacene_kazne_pregled;

-- ============================================================
-- ZAVRŠNI SAŽETAK
-- ============================================================

SELECT '========================================' AS '';

SELECT 'ZAVRŠNI SAŽETAK TESTIRANJA' AS TEST;

SELECT '========================================' AS '';

SELECT 'Testirani objekti:' AS sazatek;

SELECT '1. Procedura KreirajVozniRed - 7 testova' AS objekt;

SELECT '2. Procedura ArhivirajStareKarte - 4 testa' AS objekt;

SELECT '3. Trigger trg_vozni_red_before_insert - 3 testa (ručni)' AS objekt;

SELECT '4. Funkcija fn_izracunaj_staz_zaposlenika - 5 testova' AS objekt;

SELECT '5. View vw_neplacene_kazne_pregled - 7 testova' AS objekt;

SELECT 'Napomena: Neki testovi mogu prikazati prazne rezultate ovisno o podacima u bazi.' AS napomena;