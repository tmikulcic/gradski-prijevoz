
USE gradski_prijevoz;


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

DELIMITER //

-- ============================================================
-- PROCEDURA 11: KreirajVozniRed
-- Opis: Procedura za kreiranje voznog reda:
--       - Provjerava kompatibilnost vozila s linijom
--       - Provjerava dostupnost vozača
--       - Provjerava da vozilo nije već raspoređeno u isto vrijeme
--       - Validira kalendar
-- ============================================================
DROP PROCEDURE IF EXISTS KreirajVozniRed //

CREATE PROCEDURE KreirajVozniRed(
    IN p_linija_id INT,
    IN p_vozilo_id INT,
    IN p_vozac_id INT,
    IN p_kalendar_id INT,
    IN p_vrijeme_polaska TIME,
    OUT p_vozni_red_id INT,
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_tip_linije VARCHAR(50);
    DECLARE v_tip_vozila VARCHAR(50);
    DECLARE v_vozilo_u_prometu TINYINT;
    DECLARE v_vozac_uloga VARCHAR(100);
    DECLARE v_kalendar_postoji INT;
    DECLARE v_konflikt_vozilo INT;
    DECLARE v_konflikt_vozac INT;
    DECLARE v_kompatibilno BOOLEAN DEFAULT FALSE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom kreiranja voznog reda.';
        SET p_vozni_red_id = NULL;
    END;
    
    START TRANSACTION;
    
    -- Dohvat tipa linije
    SELECT tip_linije INTO v_tip_linije
    FROM linije WHERE id = p_linija_id;
    
    -- Dohvat podataka o vozilu
    SELECT tip_vozila, u_prometu INTO v_tip_vozila, v_vozilo_u_prometu
    FROM vozila WHERE id = p_vozilo_id;
    
    -- Dohvat uloge vozača
    SELECT naziv_uloge INTO v_vozac_uloga
    FROM zaposlenik WHERE id = p_vozac_id;
    
    -- Provjera kalendara
    SELECT COUNT(*) INTO v_kalendar_postoji
    FROM kalendari WHERE id = p_kalendar_id;
    
    IF v_tip_linije IS NULL THEN
        SET p_poruka = 'Greška: Linija ne postoji.';
        ROLLBACK;
    ELSEIF v_tip_vozila IS NULL THEN
        SET p_poruka = 'Greška: Vozilo ne postoji.';
        ROLLBACK;
    ELSEIF v_vozilo_u_prometu = 0 THEN
        SET p_poruka = 'Greška: Vozilo nije u prometu (servis/kvar).';
        ROLLBACK;
    ELSEIF v_vozac_uloga IS NULL THEN
        SET p_poruka = 'Greška: Vozač ne postoji.';
        ROLLBACK;
    ELSEIF v_kalendar_postoji = 0 THEN
        SET p_poruka = 'Greška: Kalendar ne postoji.';
        ROLLBACK;
    ELSE
        -- Provjera kompatibilnosti
        SET v_kompatibilno = CASE
            WHEN v_tip_linije = 'Tramvajska' AND v_tip_vozila = 'Tramvaj' THEN TRUE
            WHEN v_tip_linije = 'Autobusna' AND v_tip_vozila IN ('Autobus', 'Minibus', 'Kombi') THEN TRUE
            WHEN v_tip_linije IN ('Uspinjača', 'Žičara') THEN TRUE
            ELSE FALSE
        END;
        
        IF NOT v_kompatibilno THEN
            SET p_poruka = CONCAT('Greška: ', v_tip_vozila, ' nije kompatibilno s ', v_tip_linije, ' linijom.');
            ROLLBACK;
        ELSE
            -- Provjera konflikta vozila (±30 minuta)
            SELECT COUNT(*) INTO v_konflikt_vozilo
            FROM vozni_red
            WHERE vozilo_id = p_vozilo_id
              AND kalendar_id = p_kalendar_id
              AND ABS(TIME_TO_SEC(TIMEDIFF(vrijeme_polaska, p_vrijeme_polaska))) < 1800;
            
            -- Provjera konflikta vozača (±30 minuta)
            SELECT COUNT(*) INTO v_konflikt_vozac
            FROM vozni_red
            WHERE vozac_id = p_vozac_id
              AND kalendar_id = p_kalendar_id
              AND ABS(TIME_TO_SEC(TIMEDIFF(vrijeme_polaska, p_vrijeme_polaska))) < 1800;
            
            IF v_konflikt_vozilo > 0 THEN
                SET p_poruka = 'Greška: Vozilo je već raspoređeno u tom vremenskom periodu.';
                ROLLBACK;
            ELSEIF v_konflikt_vozac > 0 THEN
                SET p_poruka = 'Greška: Vozač je već raspoređen u tom vremenskom periodu.';
                ROLLBACK;
            ELSE
                -- Kreiranje voznog reda
                INSERT INTO vozni_red (linija_id, vozilo_id, vozac_id, kalendar_id, vrijeme_polaska)
                VALUES (p_linija_id, p_vozilo_id, p_vozac_id, p_kalendar_id, p_vrijeme_polaska);
                
                SET p_vozni_red_id = LAST_INSERT_ID();
                
                -- Audit log
                INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
                VALUES (
                    'vozni_red',
                    'INSERT',
                    NULL,
                    CONCAT('{"id":', p_vozni_red_id, ',"linija":', p_linija_id, ',"vozilo":', p_vozilo_id, ',"vrijeme":"', p_vrijeme_polaska, '"}'),
                    'SYSTEM'
                );
                
                SET p_poruka = CONCAT('Vozni red kreiran. ID: ', p_vozni_red_id, ', Polazak: ', p_vrijeme_polaska);
                COMMIT;
            END IF;
        END IF;
    END IF;
END //

-- ============================================================
-- PROCEDURA 12: ArhivirajStareKarte
-- Opis: Procedura za arhiviranje i čišćenje starih karata:
--       - Briše karte starije od zadanog broja dana
--       - Bilježi statistiku obrisanih karata
--       - Kreira sumarni audit log
--       - Vraća broj obrisanih zapisa
-- ============================================================
DROP PROCEDURE IF EXISTS ArhivirajStareKarte //

CREATE PROCEDURE ArhivirajStareKarte(
    IN p_starije_od_dana INT,
    OUT p_broj_obrisanih INT,
    OUT p_ukupna_vrijednost DECIMAL(12,2),
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_datum_granica DATE;
    DECLARE v_min_datum DATE;
    DECLARE v_max_datum DATE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom arhiviranja karata.';
        SET p_broj_obrisanih = 0;
    END;
    
    START TRANSACTION;
    
    -- Postavi granični datum
    SET v_datum_granica = DATE_SUB(CURDATE(), INTERVAL p_starije_od_dana DAY);
    
    -- Dohvati statistiku prije brisanja
    SELECT 
        COUNT(*),
        COALESCE(SUM(placena_cijena), 0),
        MIN(DATE(datum_kupnje)),
        MAX(DATE(datum_kupnje))
    INTO p_broj_obrisanih, p_ukupna_vrijednost, v_min_datum, v_max_datum
    FROM karta
    WHERE vrijedi_do < v_datum_granica;
    
    IF p_broj_obrisanih = 0 THEN
        SET p_poruka = 'Nema karata za arhiviranje.';
        COMMIT;
    ELSE
        -- Audit log prije brisanja
        INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
        VALUES (
            'karta',
            'DELETE',
            CONCAT('{"broj_karata":', p_broj_obrisanih, 
                   ',"ukupna_vrijednost":', p_ukupna_vrijednost,
                   ',"period":"', v_min_datum, ' - ', v_max_datum, '"}'),
            NULL,
            'SYSTEM_ARHIVIRANJE'
        );
        
        -- Brisanje starih karata
        DELETE FROM karta
        WHERE vrijedi_do < v_datum_granica;
        
        SET p_poruka = CONCAT('Arhivirano ', p_broj_obrisanih, ' karata u vrijednosti ', 
                              p_ukupna_vrijednost, ' EUR (', v_min_datum, ' - ', v_max_datum, ')');
        COMMIT;
    END IF;
END //


-- ============================================================
-- PRIMJERI POZIVA PROCEDURA:
-- ============================================================

-- 1. Kupovina karte
-- CALL KupovinaKarteKorisnik(1, 1, @kod, @cijena, @poruka);
-- SELECT @kod AS karta_kod, @cijena AS cijena, @poruka AS poruka;

-- 2. Registracija servisa
-- CALL RegistracijaServisaVozila(1, 1, 'Redovni', 250.00, 'Zamjena ulja i filtera', @servis_id, @poruka);
-- SELECT @servis_id, @poruka;

-- 3. Obrada prekršaja
-- CALL ObradaPrekrsaja(1, 1, 50.00, 'Vožnja bez karte na liniji 6', @prekrsaj_id, @suspendiran, @poruka);
-- SELECT @prekrsaj_id, @suspendiran, @poruka;

-- 4. Premještanje vozila na liniju
-- CALL PremjestiVoziloNaLiniju(1, 2, 'admin', @poruka);
-- SELECT @poruka;

-- 5. Obrada pritužbe
-- CALL ObradaPrituzbe(1, 'Riješeno', 1, 'Problem je riješen, zahvaljujemo na prijavi.', @poruka);
-- SELECT @poruka;

-- 6. Generiranje mjesečnog izvještaja
-- CALL GeneriranjeMjesecnogIzvjestaja(2026, 1, @karata, @prihod, @prekrsaja, @kazni, @servisa, @trosak, @prituzbi, @neto, @poruka);
-- SELECT @karata, @prihod, @prekrsaja, @kazni, @servisa, @trosak, @prituzbi, @neto, @poruka;

-- 7. Registracija novog korisnika
-- CALL RegistracijaNovogKorisnika('Ivan', 'Horvat', 'ivan.horvat@email.com', '1990-05-15', @id, @kategorija, @poruka);
-- SELECT @id, @kategorija, @poruka;

-- 8. Aktivacija vozila nakon servisa
-- CALL AktivirajVoziloNakonServisa(1, 1, @linija, @poruka);
-- SELECT @linija, @poruka;

-- 9. Plaćanje kazne
-- CALL PlacanjeKazne(1, 50.00, @reaktiviran, @poruka);
-- SELECT @reaktiviran, @poruka;

-- 10. Dodavanje stanice na liniju
-- CALL DodajStanicuNaLiniju(1, 5, 3, @pozicija, @poruka);
-- SELECT @pozicija, @poruka;

-- 11. Kreiranje voznog reda
-- CALL KreirajVozniRed(1, 1, 1, 1, '08:00:00', @id, @poruka);
-- SELECT @id, @poruka;

-- 12. Arhiviranje starih karata
-- CALL ArhivirajStareKarte(365, @obrisano, @vrijednost, @poruka);
-- SELECT @obrisano, @vrijednost, @poruka;

-- ============================================================
-- TRIGGER 6: trg_vozni_red_validacija
-- Opis: Prije unosa u vozni red provjerava:
--       - Je li vozilo u prometu
--       - Kompatibilnost vozila s tipom linije
--       - Konflikt rasporeda (vozilo/vozač već raspoređeni)
-- ============================================================
DROP TRIGGER IF EXISTS trg_vozni_red_before_insert //

CREATE TRIGGER trg_vozni_red_before_insert
BEFORE INSERT ON vozni_red
FOR EACH ROW
BEGIN
    DECLARE v_vozilo_u_prometu TINYINT;
    DECLARE v_tip_vozila VARCHAR(50);
    DECLARE v_tip_linije VARCHAR(50);
    DECLARE v_konflikt INT;
    DECLARE v_kompatibilno BOOLEAN DEFAULT FALSE;
    
    -- Dohvati podatke o vozilu
    SELECT u_prometu, tip_vozila INTO v_vozilo_u_prometu, v_tip_vozila
    FROM vozila
    WHERE id = NEW.vozilo_id;
    
    -- Dohvati tip linije
    SELECT tip_linije INTO v_tip_linije
    FROM linije
    WHERE id = NEW.linija_id;
    
    -- Provjera je li vozilo u prometu
    IF v_vozilo_u_prometu = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Greška: Vozilo nije u prometu (servis/kvar). Odaberite drugo vozilo.';
    END IF;
    
    -- Provjera kompatibilnosti
    SET v_kompatibilno = CASE
        WHEN v_tip_linije = 'Tramvajska' AND v_tip_vozila = 'Tramvaj' THEN TRUE
        WHEN v_tip_linije = 'Autobusna' AND v_tip_vozila IN ('Autobus', 'Minibus', 'Kombi') THEN TRUE
        WHEN v_tip_linije IN ('Uspinjača', 'Žičara') THEN TRUE
        ELSE FALSE
    END;
    
    IF NOT v_kompatibilno THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Greška: Tip vozila nije kompatibilan s tipom linije.';
    END IF;
    
    -- Provjera konflikta vozila (±30 minuta)
    SELECT COUNT(*) INTO v_konflikt
    FROM vozni_red
    WHERE vozilo_id = NEW.vozilo_id
      AND kalendar_id = NEW.kalendar_id
      AND ABS(TIME_TO_SEC(TIMEDIFF(vrijeme_polaska, NEW.vrijeme_polaska))) < 1800;
    
    IF v_konflikt > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Greška: Vozilo je već raspoređeno u tom vremenskom periodu (±30 min).';
    END IF;
    
    -- Provjera konflikta vozača (±30 minuta)
    SELECT COUNT(*) INTO v_konflikt
    FROM vozni_red
    WHERE vozac_id = NEW.vozac_id
      AND kalendar_id = NEW.kalendar_id
      AND ABS(TIME_TO_SEC(TIMEDIFF(vrijeme_polaska, NEW.vrijeme_polaska))) < 1800;
    
    IF v_konflikt > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Greška: Vozač je već raspoređen u tom vremenskom periodu (±30 min).';
    END IF;
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
