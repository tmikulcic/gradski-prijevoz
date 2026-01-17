-- ============================================================
-- BAZA: gradski_prijevoz
-- 6 SMISLENIH TRIGGERA
-- ============================================================

USE gradski_prijevoz;

-- ============================================================
-- POMOĆNE TABLICE ZA TRIGGERE
-- ============================================================

-- Tablica za praćenje svih promjena u sustavu (audit trail)
CREATE TABLE IF NOT EXISTS audit_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    tablica_naziv VARCHAR(100) NOT NULL,
    operacija ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    stari_podaci JSON,
    novi_podaci JSON,
    korisnik VARCHAR(100),
    vrijeme_promjene TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tablica za notifikacije korisnicima
CREATE TABLE IF NOT EXISTS notifikacije (
    id INT AUTO_INCREMENT PRIMARY KEY,
    korisnik_id INT NOT NULL,
    tip_notifikacije ENUM('Info', 'Upozorenje', 'Alarm') DEFAULT 'Info',
    naslov VARCHAR(255) NOT NULL,
    poruka TEXT,
    procitano BOOLEAN DEFAULT FALSE,
    datum_kreiranja TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (korisnik_id) REFERENCES korisnici (id) ON DELETE CASCADE
);

-- Tablica za dnevnu statistiku sustava (simulirani materijalizirani pogled)
CREATE TABLE IF NOT EXISTS statistika_sustava (
    datum DATE PRIMARY KEY,
    ukupno_karata_prodano INT DEFAULT 0,
    ukupan_prihod DECIMAL(12, 2) DEFAULT 0.00,
    ukupno_prekrsaja INT DEFAULT 0,
    ukupno_kazni DECIMAL(12, 2) DEFAULT 0.00,
    broj_servisa INT DEFAULT 0,
    troskovi_servisa DECIMAL(12, 2) DEFAULT 0.00,
    broj_prituzbi INT DEFAULT 0,
    zadnje_azuriranje TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ============================================================

DELIMITER //

-- ============================================================
-- TRIGGER 1: trg_korisnici_audit
-- Opis: Automatski bilježi sve promjene na tablici korisnici
--       u audit_log tablicu (INSERT, UPDATE, DELETE)
-- ============================================================
DROP TRIGGER IF EXISTS trg_korisnici_after_insert //

CREATE TRIGGER trg_korisnici_after_insert
AFTER INSERT ON korisnici
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
    VALUES (
        'korisnici',
        'INSERT',
        NULL,
        CONCAT('{"id":', NEW.id, 
               ',"ime":"', NEW.ime, 
               '","prezime":"', NEW.prezime, 
               '","email":"', COALESCE(NEW.email, ''), 
               '","status":"', NEW.status_racuna, '"}'),
        CURRENT_USER()
    );
END //

DROP TRIGGER IF EXISTS trg_korisnici_after_update //

CREATE TRIGGER trg_korisnici_after_update
AFTER UPDATE ON korisnici
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
    VALUES (
        'korisnici',
        'UPDATE',
        CONCAT('{"id":', OLD.id, 
               ',"ime":"', OLD.ime, 
               '","prezime":"', OLD.prezime, 
               '","status":"', OLD.status_racuna, '"}'),
        CONCAT('{"id":', NEW.id, 
               ',"ime":"', NEW.ime, 
               '","prezime":"', NEW.prezime, 
               '","status":"', NEW.status_racuna, '"}'),
        CURRENT_USER()
    );
    
    -- Ako je korisnik suspendiran, pošalji notifikaciju
    IF OLD.status_racuna != 'Suspendiran' AND NEW.status_racuna = 'Suspendiran' THEN
        INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
        VALUES (
            NEW.id,
            'Alarm',
            'Račun suspendiran',
            'Vaš račun je suspendiran. Molimo kontaktirajte korisničku službu.'
        );
    END IF;
    
    -- Ako je korisnik reaktiviran, pošalji notifikaciju
    IF OLD.status_racuna = 'Suspendiran' AND NEW.status_racuna = 'Aktivan' THEN
        INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
        VALUES (
            NEW.id,
            'Info',
            'Račun reaktiviran',
            'Vaš račun je ponovno aktivan. Dobrodošli natrag!'
        );
    END IF;
END //

DROP TRIGGER IF EXISTS trg_korisnici_after_delete //

CREATE TRIGGER trg_korisnici_after_delete
AFTER DELETE ON korisnici
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
    VALUES (
        'korisnici',
        'DELETE',
        CONCAT('{"id":', OLD.id, 
               ',"ime":"', OLD.ime, 
               '","prezime":"', OLD.prezime, 
               '","email":"', COALESCE(OLD.email, ''), '"}'),
        NULL,
        CURRENT_USER()
    );
END //

-- ============================================================
-- TRIGGER 2: trg_karta_statistika
-- Opis: Automatski ažurira dnevnu statistiku prodaje karata
--       prilikom svake kupovine karte
-- ============================================================
DROP TRIGGER IF EXISTS trg_karta_after_insert //

CREATE TRIGGER trg_karta_after_insert
AFTER INSERT ON karta
FOR EACH ROW
BEGIN
    DECLARE v_datum DATE;
    SET v_datum = DATE(NEW.datum_kupnje);
    
    -- Ažuriraj ili kreiraj statistiku za taj dan
    INSERT INTO statistika_sustava (datum, ukupno_karata_prodano, ukupan_prihod)
    VALUES (v_datum, 1, NEW.placena_cijena)
    ON DUPLICATE KEY UPDATE 
        ukupno_karata_prodano = ukupno_karata_prodano + 1,
        ukupan_prihod = ukupan_prihod + NEW.placena_cijena;
    
    -- Pošalji potvrdu korisniku
    INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
    VALUES (
        NEW.korisnik_id,
        'Info',
        'Karta kupljena',
        CONCAT('Vaša karta ', NEW.karta_kod, ' vrijedi do ', NEW.vrijedi_do, '. Ugodna vožnja!')
    );
END //

-- ============================================================
-- TRIGGER 3: trg_prekrsaj_statistika_notifikacija
-- Opis: Prilikom evidentiranja prekršaja:
--       - Ažurira dnevnu statistiku prekršaja
--       - Šalje upozorenje korisniku
--       - Automatski suspendira korisnika nakon 3. neplaćenog prekršaja
-- ============================================================
DROP TRIGGER IF EXISTS trg_prekrsaj_after_insert //

CREATE TRIGGER trg_prekrsaj_after_insert
AFTER INSERT ON prekrsaji
FOR EACH ROW
BEGIN
    DECLARE v_broj_neplacenih INT;
    DECLARE v_datum DATE;
    
    SET v_datum = DATE(NEW.datum_prekrsaja);
    
    -- Ažuriraj statistiku
    INSERT INTO statistika_sustava (datum, ukupno_prekrsaja, ukupno_kazni)
    VALUES (v_datum, 1, NEW.iznos_kazne)
    ON DUPLICATE KEY UPDATE 
        ukupno_prekrsaja = ukupno_prekrsaja + 1,
        ukupno_kazni = ukupno_kazni + NEW.iznos_kazne;
    
    -- Broji neplaćene prekršaje korisnika
    SELECT COUNT(*) INTO v_broj_neplacenih
    FROM prekrsaji
    WHERE korisnik_id = NEW.korisnik_id AND status_placanja = 'Neplaćeno';
    
    -- Notifikacija o prekršaju
    INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
    VALUES (
        NEW.korisnik_id,
        'Upozorenje',
        'Evidentirani prekršaj',
        CONCAT('Evidentirani ste za prekršaj. Iznos kazne: ', NEW.iznos_kazne, 
               ' EUR. Ukupno neplaćenih: ', v_broj_neplacenih)
    );
    
    -- Automatska suspenzija nakon 3 neplaćena prekršaja
    IF v_broj_neplacenih >= 3 THEN
        UPDATE korisnici
        SET status_racuna = 'Suspendiran'
        WHERE id = NEW.korisnik_id AND status_racuna != 'Suspendiran';
    END IF;
END //

-- ============================================================
-- TRIGGER 4: trg_vozilo_servis_status
-- Opis: Prilikom unosa servisa vozila:
--       - Automatski stavlja vozilo van prometa za izvanredne servise
--       - Ažurira statistiku troškova servisa
--       - Bilježi promjenu u audit log
-- ============================================================
DROP TRIGGER IF EXISTS trg_odrzavanje_after_insert //

CREATE TRIGGER trg_odrzavanje_after_insert
AFTER INSERT ON odrzavanje_vozila
FOR EACH ROW
BEGIN
    DECLARE v_staro_stanje TINYINT;
    DECLARE v_reg_oznaka VARCHAR(10);
    
    -- Dohvati trenutno stanje vozila
    SELECT u_prometu, registarska_oznaka INTO v_staro_stanje, v_reg_oznaka
    FROM vozila
    WHERE id = NEW.vozilo_id;
    
    -- Ažuriraj statistiku servisa
    INSERT INTO statistika_sustava (datum, broj_servisa, troskovi_servisa)
    VALUES (NEW.datum_servisa, 1, NEW.trosak_servisa)
    ON DUPLICATE KEY UPDATE 
        broj_servisa = broj_servisa + 1,
        troskovi_servisa = troskovi_servisa + NEW.trosak_servisa;
    
    -- Za izvanredni servis ili popravak kvara, stavi vozilo van prometa
    IF NEW.vrsta_servisa IN ('Izvanredni', 'Popravak kvar') AND v_staro_stanje = 1 THEN
        UPDATE vozila
        SET u_prometu = 0
        WHERE id = NEW.vozilo_id;
        
        -- Audit log za promjenu statusa
        INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
        VALUES (
            'vozila',
            'UPDATE',
            CONCAT('{"id":', NEW.vozilo_id, ',"registarska_oznaka":"', v_reg_oznaka, '","u_prometu":1}'),
            CONCAT('{"id":', NEW.vozilo_id, ',"registarska_oznaka":"', v_reg_oznaka, '","u_prometu":0,"razlog":"', NEW.vrsta_servisa, '"}'),
            CONCAT('servis_id:', NEW.id)
        );
    END IF;
END //

-- ============================================================
-- TRIGGER 5: trg_prituzba_statistika
-- Opis: Prilikom kreiranja ili ažuriranja pritužbe:
--       - Ažurira statistiku pritužbi
--       - Šalje notifikaciju korisniku o statusu
--       - Bilježi promjene statusa
-- ============================================================
DROP TRIGGER IF EXISTS trg_prituzba_after_insert //

CREATE TRIGGER trg_prituzba_after_insert
AFTER INSERT ON prituzbe
FOR EACH ROW
BEGIN
    DECLARE v_datum DATE;
    SET v_datum = DATE(NEW.datum_prituzbe);
    
    -- Ažuriraj statistiku
    INSERT INTO statistika_sustava (datum, broj_prituzbi)
    VALUES (v_datum, 1)
    ON DUPLICATE KEY UPDATE 
        broj_prituzbi = broj_prituzbi + 1;
    
    -- Potvrda primitka pritužbe
    INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
    VALUES (
        NEW.korisnik_id,
        'Info',
        'Pritužba zaprimljena',
        CONCAT('Vaša pritužba (#', NEW.id, ') kategorije "', NEW.kategorija_prituzbe, 
               '" je zaprimljena. Status: ', NEW.status_rjesavanja)
    );
END //

DROP TRIGGER IF EXISTS trg_prituzba_after_update //

CREATE TRIGGER trg_prituzba_after_update
AFTER UPDATE ON prituzbe
FOR EACH ROW
BEGIN
    -- Ako se status promijenio, obavijesti korisnika
    IF OLD.status_rjesavanja != NEW.status_rjesavanja THEN
        INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
        VALUES (
            NEW.korisnik_id,
            CASE 
                WHEN NEW.status_rjesavanja = 'Riješeno' THEN 'Info'
                WHEN NEW.status_rjesavanja = 'Odbačeno' THEN 'Upozorenje'
                ELSE 'Info'
            END,
            CONCAT('Pritužba #', NEW.id, ' - ažuriran status'),
            CONCAT('Status vaše pritužbe je promijenjen iz "', OLD.status_rjesavanja, 
                   '" u "', NEW.status_rjesavanja, '".')
        );
        
        -- Audit log
        INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
        VALUES (
            'prituzbe',
            'UPDATE',
            CONCAT('{"id":', OLD.id, ',"status":"', OLD.status_rjesavanja, '"}'),
            CONCAT('{"id":', NEW.id, ',"status":"', NEW.status_rjesavanja, '"}'),
            CURRENT_USER()
        );
    END IF;
END //

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

DELIMITER ;

-- ============================================================
-- SAŽETAK TRIGGERA:
-- ============================================================
-- 1. trg_korisnici_after_insert/update/delete - Audit log za korisnike + notifikacije o statusu
-- 2. trg_karta_after_insert - Statistika prodaje + potvrda kupovine
-- 3. trg_prekrsaj_after_insert - Statistika + notifikacija + auto-suspenzija
-- 4. trg_odrzavanje_after_insert - Statistika servisa + auto status vozila
-- 5. trg_prituzba_after_insert/update - Statistika + notifikacije o statusu
-- 6. trg_vozni_red_before_insert - Validacija kompatibilnosti i konflikata
-- ============================================================