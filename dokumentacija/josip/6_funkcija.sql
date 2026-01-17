-- ============================================================
-- BAZA: gradski_prijevoz
-- 6 SMISLENIH FUNKCIJA
-- ============================================================

USE gradski_prijevoz;

DELIMITER //

-- ============================================================
-- FUNKCIJA 1: fn_izracunaj_cijenu_karte
-- Opis: Računa konačnu cijenu karte za korisnika uzimajući u obzir:
--       - Osnovnu cijenu tipa karte
--       - Popust prema kategoriji putnika (student, umirovljenik, itd.)
--       - Dodatni popust za vjerne korisnike (>10 karata = 5%, >50 = 10%)
-- Korištenje: SELECT fn_izracunaj_cijenu_karte(1, 1);
-- ============================================================
DROP FUNCTION IF EXISTS fn_izracunaj_cijenu_karte //

CREATE FUNCTION fn_izracunaj_cijenu_karte(
    p_korisnik_id INT,
    p_tip_karte_id INT
) 
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_osnovna_cijena DECIMAL(10,2);
    DECLARE v_popust_kategorija DECIMAL(5,2) DEFAULT 0;
    DECLARE v_popust_vjernost DECIMAL(5,2) DEFAULT 0;
    DECLARE v_broj_karata INT DEFAULT 0;
    DECLARE v_konacna_cijena DECIMAL(10,2);
    DECLARE v_status_korisnika VARCHAR(20);
    
    -- Provjeri status korisnika
    SELECT status_racuna INTO v_status_korisnika
    FROM korisnici
    WHERE id = p_korisnik_id;
    
    -- Ako korisnik ne postoji ili je suspendiran, vrati -1
    IF v_status_korisnika IS NULL THEN
        RETURN -1;
    END IF;
    
    IF v_status_korisnika = 'Suspendiran' THEN
        RETURN -2;
    END IF;
    
    -- Dohvati osnovnu cijenu karte
    SELECT osnovna_cijena INTO v_osnovna_cijena
    FROM tip_karte
    WHERE id = p_tip_karte_id;
    
    IF v_osnovna_cijena IS NULL THEN
        RETURN -3;
    END IF;
    
    -- Dohvati popust kategorije
    SELECT COALESCE(kp.postotak_popusta, 0) INTO v_popust_kategorija
    FROM korisnici k
    LEFT JOIN kategorija_putnik kp ON k.kategorija_id = kp.id
    WHERE k.id = p_korisnik_id;
    
    -- Izračunaj popust vjernosti (broj prethodno kupljenih karata)
    SELECT COUNT(*) INTO v_broj_karata
    FROM karta
    WHERE korisnik_id = p_korisnik_id;
    
    IF v_broj_karata > 50 THEN
        SET v_popust_vjernost = 10.00;
    ELSEIF v_broj_karata > 10 THEN
        SET v_popust_vjernost = 5.00;
    END IF;
    
    -- Izračunaj konačnu cijenu (popusti se zbrajaju, max 50%)
    SET v_konacna_cijena = v_osnovna_cijena * (1 - LEAST(v_popust_kategorija + v_popust_vjernost, 50) / 100);
    
    -- Minimalna cijena je 0.50 EUR
    RETURN GREATEST(v_konacna_cijena, 0.50);
END //

-- ============================================================
-- FUNKCIJA 2: fn_provjeri_valjanost_karte
-- Opis: Provjerava je li karta valjana i vraća status:
--       0 = Nevaljana (istekla ili ne postoji)
--       1 = Valjana
--       2 = Valjana ali ističe u roku 10 minuta
--       3 = Karta ne postoji
--       4 = Korisnik suspendiran
-- Korištenje: SELECT fn_provjeri_valjanost_karte('KRT-20260110-00001-1234');
-- ============================================================
DROP FUNCTION IF EXISTS fn_provjeri_valjanost_karte //

CREATE FUNCTION fn_provjeri_valjanost_karte(
    p_karta_kod VARCHAR(50)
) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_vrijedi_do DATETIME;
    DECLARE v_korisnik_id INT;
    DECLARE v_status_korisnika VARCHAR(20);
    DECLARE v_minuta_do_isteka INT;
    
    -- Dohvati podatke o karti
    SELECT vrijedi_do, korisnik_id INTO v_vrijedi_do, v_korisnik_id
    FROM karta
    WHERE karta_kod = p_karta_kod;
    
    -- Karta ne postoji
    IF v_vrijedi_do IS NULL THEN
        RETURN 3;
    END IF;
    
    -- Provjeri status korisnika
    SELECT status_racuna INTO v_status_korisnika
    FROM korisnici
    WHERE id = v_korisnik_id;
    
    IF v_status_korisnika = 'Suspendiran' THEN
        RETURN 4;
    END IF;
    
    -- Karta istekla
    IF v_vrijedi_do < NOW() THEN
        RETURN 0;
    END IF;
    
    -- Izračunaj minute do isteka
    SET v_minuta_do_isteka = TIMESTAMPDIFF(MINUTE, NOW(), v_vrijedi_do);
    
    -- Ističe uskoro (< 10 minuta)
    IF v_minuta_do_isteka <= 10 THEN
        RETURN 2;
    END IF;
    
    -- Valjana
    RETURN 1;
END //

-- ============================================================
-- FUNKCIJA 3: fn_odredi_kategoriju_po_dobi
-- Opis: Određuje najpovoljniju kategoriju putnika prema dobi
--       Vraća ID kategorije s najvećim popustom za tu dob
-- Korištenje: SELECT fn_odredi_kategoriju_po_dobi('1990-05-15');
-- ============================================================
DROP FUNCTION IF EXISTS fn_odredi_kategoriju_po_dobi //

CREATE FUNCTION fn_odredi_kategoriju_po_dobi(
    p_datum_rodenja DATE
) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_dob INT;
    DECLARE v_kategorija_id INT;
    
    -- Izračunaj dob
    SET v_dob = TIMESTAMPDIFF(YEAR, p_datum_rodenja, CURDATE());
    
    -- Provjeri granice
    IF v_dob < 0 OR v_dob > 150 THEN
        RETURN NULL;
    END IF;
    
    -- Pronađi kategoriju s najvećim popustom za tu dob
    SELECT id INTO v_kategorija_id
    FROM kategorija_putnik
    WHERE v_dob >= COALESCE(min_dob, 0) 
      AND v_dob <= COALESCE(max_dob, 150)
    ORDER BY postotak_popusta DESC
    LIMIT 1;
    
    -- Ako nije pronađena, vrati prvu kategoriju (default)
    IF v_kategorija_id IS NULL THEN
        SELECT id INTO v_kategorija_id
        FROM kategorija_putnik
        ORDER BY postotak_popusta ASC
        LIMIT 1;
    END IF;
    
    RETURN v_kategorija_id;
END //

-- ============================================================
-- FUNKCIJA 4: fn_broj_stanica_izmedu
-- Opis: Računa broj stanica između dvije stanice na istoj liniji
--       Vraća -1 ako stanice nisu na istoj liniji
--       Vraća -2 ako neka stanica ne postoji
-- Korištenje: SELECT fn_broj_stanica_izmedu(1, 1, 5);
-- ============================================================
DROP FUNCTION IF EXISTS fn_broj_stanica_izmedu //

CREATE FUNCTION fn_broj_stanica_izmedu(
    p_linija_id INT,
    p_stanica_od_id INT,
    p_stanica_do_id INT
) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_redoslijed_od INT;
    DECLARE v_redoslijed_do INT;
    DECLARE v_razlika INT;
    
    -- Dohvati redoslijed početne stanice
    SELECT redoslijed INTO v_redoslijed_od
    FROM linije_stanice
    WHERE linija_id = p_linija_id AND stanica_id = p_stanica_od_id;
    
    -- Dohvati redoslijed završne stanice
    SELECT redoslijed INTO v_redoslijed_do
    FROM linije_stanice
    WHERE linija_id = p_linija_id AND stanica_id = p_stanica_do_id;
    
    -- Provjeri postoje li obje stanice na liniji
    IF v_redoslijed_od IS NULL OR v_redoslijed_do IS NULL THEN
        RETURN -1;
    END IF;
    
    -- Izračunaj razliku (apsolutna vrijednost jer može biti u oba smjera)
    SET v_razlika = ABS(v_redoslijed_do - v_redoslijed_od);
    
    RETURN v_razlika;
END //

-- ============================================================
-- FUNKCIJA 5: fn_provjeri_dostupnost_vozila
-- Opis: Provjerava je li vozilo dostupno u određeno vrijeme
--       Vraća:
--       1 = Dostupno
--       0 = Nije dostupno (već raspoređeno ±30 min)
--       -1 = Vozilo van prometa (servis/kvar)
--       -2 = Vozilo ne postoji
--       -3 = Nekompatibilno s tipom linije
-- Korištenje: SELECT fn_provjeri_dostupnost_vozila(1, 1, 1, '08:30:00');
-- ============================================================
DROP FUNCTION IF EXISTS fn_provjeri_dostupnost_vozila //

CREATE FUNCTION fn_provjeri_dostupnost_vozila(
    p_vozilo_id INT,
    p_linija_id INT,
    p_kalendar_id INT,
    p_vrijeme TIME
) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_u_prometu TINYINT;
    DECLARE v_tip_vozila VARCHAR(50);
    DECLARE v_tip_linije VARCHAR(50);
    DECLARE v_konflikt INT;
    DECLARE v_kompatibilno BOOLEAN DEFAULT FALSE;
    
    -- Dohvati podatke o vozilu
    SELECT u_prometu, tip_vozila INTO v_u_prometu, v_tip_vozila
    FROM vozila
    WHERE id = p_vozilo_id;
    
    -- Vozilo ne postoji
    IF v_tip_vozila IS NULL THEN
        RETURN -2;
    END IF;
    
    -- Vozilo van prometa
    IF v_u_prometu = 0 THEN
        RETURN -1;
    END IF;
    
    -- Dohvati tip linije
    SELECT tip_linije INTO v_tip_linije
    FROM linije
    WHERE id = p_linija_id;
    
    -- Provjera kompatibilnosti
    SET v_kompatibilno = CASE
        WHEN v_tip_linije = 'Tramvajska' AND v_tip_vozila = 'Tramvaj' THEN TRUE
        WHEN v_tip_linije = 'Autobusna' AND v_tip_vozila IN ('Autobus', 'Minibus', 'Kombi') THEN TRUE
        WHEN v_tip_linije IN ('Uspinjača', 'Žičara') THEN TRUE
        WHEN v_tip_linije IS NULL THEN TRUE
        ELSE FALSE
    END;
    
    IF NOT v_kompatibilno THEN
        RETURN -3;
    END IF;
    
    -- Provjera konflikta (±30 minuta)
    SELECT COUNT(*) INTO v_konflikt
    FROM vozni_red
    WHERE vozilo_id = p_vozilo_id
      AND kalendar_id = p_kalendar_id
      AND ABS(TIME_TO_SEC(TIMEDIFF(vrijeme_polaska, p_vrijeme))) < 1800;
    
    IF v_konflikt > 0 THEN
        RETURN 0;
    END IF;
    
    RETURN 1;
END //

-- ============================================================
-- FUNKCIJA 6: fn_izracunaj_staz_zaposlenika
-- Opis: Računa radni staž zaposlenika i vraća formatirani string
--       Format: "X godina, Y mjeseci, Z dana"
--       Ako zaposlenik ne postoji, vraća NULL
-- Korištenje: SELECT fn_izracunaj_staz_zaposlenika(1);
-- ============================================================
DROP FUNCTION IF EXISTS fn_izracunaj_staz_zaposlenika //

CREATE FUNCTION fn_izracunaj_staz_zaposlenika(
    p_zaposlenik_id INT
) 
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_datum_zaposlenja DATE;
    DECLARE v_godine INT;
    DECLARE v_mjeseci INT;
    DECLARE v_dani INT;
    DECLARE v_ukupno_dana INT;
    DECLARE v_rezultat VARCHAR(100);
    
    -- Dohvati datum zaposlenja
    SELECT datum_zaposlenja INTO v_datum_zaposlenja
    FROM zaposlenik
    WHERE id = p_zaposlenik_id;
    
    -- Zaposlenik ne postoji
    IF v_datum_zaposlenja IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Ako je datum u budućnosti
    IF v_datum_zaposlenja > CURDATE() THEN
        RETURN 'Još nije započeo radni odnos';
    END IF;
    
    -- Izračunaj komponente staža
    SET v_godine = TIMESTAMPDIFF(YEAR, v_datum_zaposlenja, CURDATE());
    SET v_mjeseci = TIMESTAMPDIFF(MONTH, v_datum_zaposlenja, CURDATE()) - (v_godine * 12);
    SET v_ukupno_dana = DATEDIFF(CURDATE(), v_datum_zaposlenja);
    SET v_dani = v_ukupno_dana - (v_godine * 365) - (v_mjeseci * 30);
    
    -- Korekcija za negativne dane
    IF v_dani < 0 THEN
        SET v_mjeseci = v_mjeseci - 1;
        SET v_dani = v_dani + 30;
    END IF;
    
    -- Formatiraj rezultat
    SET v_rezultat = CONCAT(
        v_godine, ' god, ',
        v_mjeseci, ' mj, ',
        v_dani, ' dana',
        ' (ukupno ', v_ukupno_dana, ' dana)'
    );
    
    RETURN v_rezultat;
END //

DELIMITER ;

-- ============================================================
-- SAŽETAK FUNKCIJA:
-- ============================================================
-- 1. fn_izracunaj_cijenu_karte     - Cijena s popustom kategorije i vjernosti
-- 2. fn_provjeri_valjanost_karte   - Status karte (valjana/istekla/uskoro ističe)
-- 3. fn_odredi_kategoriju_po_dobi  - Najpovoljnija kategorija za dob
-- 4. fn_broj_stanica_izmedu        - Udaljenost u stanicama na liniji
-- 5. fn_provjeri_dostupnost_vozila - Dostupnost vozila u vremenu
-- 6. fn_izracunaj_staz_zaposlenika - Radni staž u godinama/mjesecima/danima
-- ============================================================

-- ============================================================
-- PRIMJERI KORIŠTENJA:
-- ============================================================

-- Izračunaj cijenu karte za korisnika 1, tip karte 1
-- SELECT fn_izracunaj_cijenu_karte(1, 1) AS cijena;

-- Provjeri valjanost karte
-- SELECT fn_provjeri_valjanost_karte('KRT-20260110-00001-1234') AS status;
-- Tumačenje: 0=Istekla, 1=Valjana, 2=Ističe uskoro, 3=Ne postoji, 4=Suspendiran

-- Odredi kategoriju za osobu rođenu 1955.
-- SELECT fn_odredi_kategoriju_po_dobi('1955-03-20') AS kategorija_id;

-- Broj stanica između stanice 1 i 5 na liniji 1
-- SELECT fn_broj_stanica_izmedu(1, 1, 5) AS broj_stanica;

-- Je li vozilo 1 dostupno u 8:30 na liniji 1?
-- SELECT fn_provjeri_dostupnost_vozila(1, 1, 1, '08:30:00') AS dostupnost;
-- Tumačenje: 1=Da, 0=Ne (konflikt), -1=Van prometa, -2=Ne postoji, -3=Nekompatibilno

-- Staž zaposlenika 1
-- SELECT fn_izracunaj_staz_zaposlenika(1) AS radni_staz;