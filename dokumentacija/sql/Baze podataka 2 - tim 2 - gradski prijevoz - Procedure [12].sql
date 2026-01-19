-- ============================================================
-- BAZA: gradski_prijevoz
-- 6 SMISLENIH PROCEDURA S TRANSAKCIJAMA
-- ============================================================

USE gradski_prijevoz;

DELIMITER //

-- ============================================================
-- PROCEDURA 1: KupovinaKarteKorisnik
-- Opis: Kompleksna procedura za kupovinu karte koja:
--       - Provjerava status korisnika
--       - Računa popust na temelju kategorije putnika
--       - Generira jedinstveni kod karte
--       - Ažurira dnevnu statistiku
--       - Šalje notifikaciju korisniku
-- ============================================================
DROP PROCEDURE IF EXISTS KupovinaKarteKorisnik //

CREATE PROCEDURE KupovinaKarteKorisnik(
    IN p_korisnik_id INT,
    IN p_tip_karte_id INT,
    OUT p_karta_kod VARCHAR(50),
    OUT p_konacna_cijena DECIMAL(10,2),
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_status_racuna VARCHAR(20);
    DECLARE v_kategorija_id INT;
    DECLARE v_postotak_popusta DECIMAL(5,2);
    DECLARE v_osnovna_cijena DECIMAL(10,2);
    DECLARE v_trajanje_minute INT;
    DECLARE v_vrijedi_do DATETIME;
    DECLARE v_datum_danas DATE;
    DECLARE v_error_occurred BOOLEAN DEFAULT FALSE;
    
    -- Handler za greške
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        SET v_error_occurred = TRUE;
    END;
    
    -- Početak transakcije
    START TRANSACTION;
    
    -- Provjera statusa korisnika
    SELECT status_racuna, kategorija_id INTO v_status_racuna, v_kategorija_id
    FROM korisnici
    WHERE id = p_korisnik_id;
    
    -- Ako korisnik ne postoji ili nije aktivan
    IF v_status_racuna IS NULL THEN
        SET p_poruka = 'Greška: Korisnik ne postoji.';
        ROLLBACK;
    ELSEIF v_status_racuna != 'Aktivan' THEN
        SET p_poruka = CONCAT('Greška: Korisnik ima status: ', v_status_racuna);
        ROLLBACK;
    ELSE
        -- Dohvat podataka o tipu karte
        SELECT osnovna_cijena, trajanje_minute INTO v_osnovna_cijena, v_trajanje_minute
        FROM tip_karte
        WHERE id = p_tip_karte_id;
        
        IF v_osnovna_cijena IS NULL THEN
            SET p_poruka = 'Greška: Tip karte ne postoji.';
            ROLLBACK;
        ELSE
            -- Dohvat popusta za kategoriju putnika
            SELECT COALESCE(postotak_popusta, 0) INTO v_postotak_popusta
            FROM kategorija_putnik
            WHERE id = v_kategorija_id;
            
            -- Izračun konačne cijene
            SET p_konacna_cijena = v_osnovna_cijena * (1 - v_postotak_popusta / 100);
            
            -- Generiranje jedinstvenog koda karte
            SET p_karta_kod = CONCAT(
                'KRT-',
                DATE_FORMAT(NOW(), '%Y%m%d'),
                '-',
                LPAD(p_korisnik_id, 5, '0'),
                '-',
                LPAD(FLOOR(RAND() * 10000), 4, '0')
            );
            
            -- Izračun datuma isteka
            SET v_vrijedi_do = DATE_ADD(NOW(), INTERVAL v_trajanje_minute MINUTE);
            SET v_datum_danas = CURDATE();
            
            -- Unos nove karte
            INSERT INTO karta (tip_karte_id, korisnik_id, karta_kod, datum_kupnje, vrijedi_do, placena_cijena)
            VALUES (p_tip_karte_id, p_korisnik_id, p_karta_kod, NOW(), v_vrijedi_do, p_konacna_cijena);
            
            -- Ažuriranje dnevne statistike
            INSERT INTO statistika_sustava (datum, ukupno_karata_prodano, ukupan_prihod)
            VALUES (v_datum_danas, 1, p_konacna_cijena)
            ON DUPLICATE KEY UPDATE 
                ukupno_karata_prodano = ukupno_karata_prodano + 1,
                ukupan_prihod = ukupan_prihod + p_konacna_cijena;
            
            -- Slanje notifikacije korisniku
            INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
            VALUES (
                p_korisnik_id, 
                'Info', 
                'Karta kupljena',
                CONCAT('Vaša karta ', p_karta_kod, ' je uspješno kupljena. Vrijedi do: ', v_vrijedi_do)
            );
            
            -- Provjera je li došlo do greške
            IF v_error_occurred THEN
                SET p_poruka = 'Greška prilikom kupovine karte.';
                ROLLBACK;
            ELSE
                SET p_poruka = 'Karta uspješno kupljena!';
                COMMIT;
            END IF;
        END IF;
    END IF;
END //

-- ============================================================
-- PROCEDURA 2: RegistracijaServisaVozila
-- Opis: Procedura za registraciju servisa vozila koja:
--       - Provjerava postoji li vozilo
--       - Automatski stavlja vozilo van prometa ako je izvanredni servis
--       - Bilježi servis u odrzavanje_vozila
--       - Ažurira statistiku troškova servisa
--       - Kreira audit log zapis
-- ============================================================
DROP PROCEDURE IF EXISTS RegistracijaServisaVozila //

CREATE PROCEDURE RegistracijaServisaVozila(
    IN p_vozilo_id INT,
    IN p_zaposlenik_id INT,
    IN p_vrsta_servisa ENUM('Redovni','Izvanredni','Tehnički pregled','Popravak kvar'),
    IN p_trosak_servisa DECIMAL(10,2),
    IN p_opis_radova TEXT,
    OUT p_servis_id INT,
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_vozilo_postoji INT;
    DECLARE v_zaposlenik_postoji INT;
    DECLARE v_reg_oznaka VARCHAR(10);
    DECLARE v_datum_danas DATE;
    DECLARE v_staro_stanje TINYINT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška: Transakcija poništena zbog greške u bazi.';
        SET p_servis_id = NULL;
    END;
    
    START TRANSACTION;
    
    -- Provjera vozila
    SELECT COUNT(*), u_prometu, registarska_oznaka 
    INTO v_vozilo_postoji, v_staro_stanje, v_reg_oznaka
    FROM vozila 
    WHERE id = p_vozilo_id
    GROUP BY u_prometu, registarska_oznaka;
    
    -- Provjera zaposlenika
    SELECT COUNT(*) INTO v_zaposlenik_postoji
    FROM zaposlenik 
    WHERE id = p_zaposlenik_id;
    
    IF v_vozilo_postoji = 0 THEN
        SET p_poruka = 'Greška: Vozilo ne postoji.';
        ROLLBACK;
    ELSEIF v_zaposlenik_postoji = 0 THEN
        SET p_poruka = 'Greška: Zaposlenik ne postoji.';
        ROLLBACK;
    ELSE
        SET v_datum_danas = CURDATE();
        
        -- Unos servisa
        INSERT INTO odrzavanje_vozila (vozilo_id, zaposlenik_id, datum_servisa, vrsta_servisa, trosak_servisa, opis_radova)
        VALUES (p_vozilo_id, p_zaposlenik_id, v_datum_danas, p_vrsta_servisa, p_trosak_servisa, p_opis_radova);
        
        SET p_servis_id = LAST_INSERT_ID();
        
        -- Ako je izvanredni servis ili popravak kvara, stavi vozilo van prometa
        IF p_vrsta_servisa IN ('Izvanredni', 'Popravak kvar') THEN
            UPDATE vozila 
            SET u_prometu = 0 
            WHERE id = p_vozilo_id;
            
            -- Audit log za promjenu statusa
            INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
            VALUES (
                'vozila',
                'UPDATE',
                CONCAT('{"id":', p_vozilo_id, ',"u_prometu":', v_staro_stanje, '}'),
                CONCAT('{"id":', p_vozilo_id, ',"u_prometu":0}'),
                CONCAT('zaposlenik_id:', p_zaposlenik_id)
            );
        END IF;
        
        -- Ažuriranje statistike
        INSERT INTO statistika_sustava (datum, broj_servisa, troskovi_servisa)
        VALUES (v_datum_danas, 1, p_trosak_servisa)
        ON DUPLICATE KEY UPDATE 
            broj_servisa = broj_servisa + 1,
            troskovi_servisa = troskovi_servisa + p_trosak_servisa;
        
        SET p_poruka = CONCAT('Servis uspješno registriran za vozilo ', v_reg_oznaka);
        COMMIT;
    END IF;
END //

-- ============================================================
-- PROCEDURA 3: ObradaPrekrsaja
-- Opis: Procedura za obradu prekršaja vožnje bez karte:
--       - Kreira prekršaj
--       - Suspendira korisnika nakon 3 neplaćena prekršaja
--       - Ažurira statistiku prekršaja
--       - Šalje upozorenje korisniku
-- ============================================================
DROP PROCEDURE IF EXISTS ObradaPrekrsaja //

CREATE PROCEDURE ObradaPrekrsaja(
    IN p_korisnik_id INT,
    IN p_zaposlenik_id INT,
    IN p_iznos_kazne DECIMAL(10,2),
    IN p_napomena TEXT,
    OUT p_prekrsaj_id INT,
    OUT p_korisnik_suspendiran BOOLEAN,
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_broj_neplacenih INT DEFAULT 0;
    DECLARE v_korisnik_ime VARCHAR(100);
    DECLARE v_datum_danas DATE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom obrade prekršaja.';
        SET p_prekrsaj_id = NULL;
        SET p_korisnik_suspendiran = FALSE;
    END;
    
    START TRANSACTION;
    
    SET v_datum_danas = CURDATE();
    SET p_korisnik_suspendiran = FALSE;
    
    -- Provjera korisnika
    SELECT CONCAT(ime, ' ', prezime) INTO v_korisnik_ime
    FROM korisnici
    WHERE id = p_korisnik_id;
    
    IF v_korisnik_ime IS NULL THEN
        SET p_poruka = 'Greška: Korisnik ne postoji.';
        ROLLBACK;
    ELSE
        -- Kreiranje prekršaja
        INSERT INTO prekrsaji (korisnik_id, zaposlenik_id, iznos_kazne, status_placanja, napomena)
        VALUES (p_korisnik_id, p_zaposlenik_id, p_iznos_kazne, 'Neplaćeno', p_napomena);
        
        SET p_prekrsaj_id = LAST_INSERT_ID();
        
        -- Brojanje neplaćenih prekršaja
        SELECT COUNT(*) INTO v_broj_neplacenih
        FROM prekrsaji
        WHERE korisnik_id = p_korisnik_id AND status_placanja = 'Neplaćeno';
        
        -- Suspenzija nakon 3 neplaćena prekršaja
        IF v_broj_neplacenih >= 3 THEN
            UPDATE korisnici
            SET status_racuna = 'Suspendiran'
            WHERE id = p_korisnik_id;
            
            SET p_korisnik_suspendiran = TRUE;
            
            -- Notifikacija o suspenziji
            INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
            VALUES (
                p_korisnik_id,
                'Alarm',
                'Račun suspendiran',
                CONCAT('Vaš račun je suspendiran zbog ', v_broj_neplacenih, ' neplaćenih prekršaja. Molimo podmirit dugovanja.')
            );
        ELSE
            -- Upozorenje o prekršaju
            INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
            VALUES (
                p_korisnik_id,
                'Upozorenje',
                'Novi prekršaj',
                CONCAT('Evidentirani ste za prekršaj. Iznos kazne: ', p_iznos_kazne, ' EUR. Broj neplaćenih: ', v_broj_neplacenih)
            );
        END IF;
        
        -- Ažuriranje statistike
        INSERT INTO statistika_sustava (datum, ukupno_prekrsaja, ukupno_kazni)
        VALUES (v_datum_danas, 1, p_iznos_kazne)
        ON DUPLICATE KEY UPDATE 
            ukupno_prekrsaja = ukupno_prekrsaja + 1,
            ukupno_kazni = ukupno_kazni + p_iznos_kazne;
        
        IF p_korisnik_suspendiran THEN
            SET p_poruka = CONCAT('Prekršaj evidentiran. Korisnik ', v_korisnik_ime, ' je SUSPENDIRAN.');
        ELSE
            SET p_poruka = CONCAT('Prekršaj evidentiran za korisnika ', v_korisnik_ime, '. Neplaćenih: ', v_broj_neplacenih);
        END IF;
        
        COMMIT;
    END IF;
END //

-- ============================================================
-- PROCEDURA 4: PremjestiVoziloNaLiniju
-- Opis: Procedura za preraspodelu vozila na drugu liniju:
--       - Provjerava kompatibilnost tipa vozila s tipom linije
--       - Provjerava je li vozilo u prometu
--       - Ažurira vozni red
--       - Bilježi promjenu u audit log
-- ============================================================
DROP PROCEDURE IF EXISTS PremjestiVoziloNaLiniju //

CREATE PROCEDURE PremjestiVoziloNaLiniju(
    IN p_vozni_red_id INT,
    IN p_novo_vozilo_id INT,
    IN p_korisnik VARCHAR(100),
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_staro_vozilo_id INT;
    DECLARE v_linija_id INT;
    DECLARE v_tip_linije VARCHAR(50);
    DECLARE v_tip_vozila VARCHAR(50);
    DECLARE v_u_prometu TINYINT;
    DECLARE v_kompatibilno BOOLEAN DEFAULT FALSE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom premještanja vozila.';
    END;
    
    START TRANSACTION;
    
    -- Dohvat podataka o voznom redu
    SELECT vozilo_id, linija_id INTO v_staro_vozilo_id, v_linija_id
    FROM vozni_red
    WHERE id = p_vozni_red_id;
    
    IF v_staro_vozilo_id IS NULL THEN
        SET p_poruka = 'Greška: Vozni red ne postoji.';
        ROLLBACK;
    ELSE
        -- Dohvat tipa linije
        SELECT tip_linije INTO v_tip_linije
        FROM linije
        WHERE id = v_linija_id;
        
        -- Dohvat podataka o novom vozilu
        SELECT tip_vozila, u_prometu INTO v_tip_vozila, v_u_prometu
        FROM vozila
        WHERE id = p_novo_vozilo_id;
        
        IF v_tip_vozila IS NULL THEN
            SET p_poruka = 'Greška: Vozilo ne postoji.';
            ROLLBACK;
        ELSEIF v_u_prometu = 0 THEN
            SET p_poruka = 'Greška: Vozilo nije u prometu (servis/kvar).';
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
                SET p_poruka = CONCAT('Greška: Vozilo tipa ', v_tip_vozila, ' nije kompatibilno s linijom tipa ', v_tip_linije);
                ROLLBACK;
            ELSE
                -- Ažuriranje voznog reda
                UPDATE vozni_red
                SET vozilo_id = p_novo_vozilo_id
                WHERE id = p_vozni_red_id;
                
                -- Audit log
                INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
                VALUES (
                    'vozni_red',
                    'UPDATE',
                    CONCAT('{"id":', p_vozni_red_id, ',"vozilo_id":', v_staro_vozilo_id, '}'),
                    CONCAT('{"id":', p_vozni_red_id, ',"vozilo_id":', p_novo_vozilo_id, '}'),
                    p_korisnik
                );
                
                SET p_poruka = CONCAT('Vozilo uspješno premješteno na liniju. Staro: ', v_staro_vozilo_id, ', Novo: ', p_novo_vozilo_id);
                COMMIT;
            END IF;
        END IF;
    END IF;
END //

-- ============================================================
-- PROCEDURA 5: ObradaPrituzbe
-- Opis: Procedura za obradu pritužbe korisnika:
--       - Mijenja status pritužbe
--       - Ako je kategorija "Kvar vozila", automatski planira servis
--       - Šalje notifikaciju korisniku o statusu
--       - Ažurira statistiku pritužbi
-- ============================================================
DROP PROCEDURE IF EXISTS ObradaPrituzbe //

CREATE PROCEDURE ObradaPrituzbe(
    IN p_prituzba_id INT,
    IN p_novi_status ENUM('Novo','U obradi','Riješeno','Odbačeno'),
    IN p_zaposlenik_id INT,
    IN p_odgovor TEXT,
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_korisnik_id INT;
    DECLARE v_linija_id INT;
    DECLARE v_kategorija_prituzbe VARCHAR(50);
    DECLARE v_stari_status VARCHAR(20);
    DECLARE v_vozilo_id INT;
    DECLARE v_datum_danas DATE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom obrade pritužbe.';
    END;
    
    START TRANSACTION;
    
    SET v_datum_danas = CURDATE();
    
    -- Dohvat podataka o pritužbi
    SELECT korisnik_id, linija_id, kategorija_prituzbe, status_rjesavanja
    INTO v_korisnik_id, v_linija_id, v_kategorija_prituzbe, v_stari_status
    FROM prituzbe
    WHERE id = p_prituzba_id;
    
    IF v_korisnik_id IS NULL THEN
        SET p_poruka = 'Greška: Pritužba ne postoji.';
        ROLLBACK;
    ELSEIF v_stari_status IN ('Riješeno', 'Odbačeno') THEN
        SET p_poruka = CONCAT('Greška: Pritužba je već ', v_stari_status);
        ROLLBACK;
    ELSE
        -- Ažuriranje statusa pritužbe
        UPDATE prituzbe
        SET status_rjesavanja = p_novi_status
        WHERE id = p_prituzba_id;
        
        -- Ako je kvar vozila i riješeno, planiraj servis
        IF v_kategorija_prituzbe = 'Kvar vozila' AND p_novi_status = 'Riješeno' AND v_linija_id IS NOT NULL THEN
            -- Pronađi vozilo na toj liniji
            SELECT vozilo_id INTO v_vozilo_id
            FROM vozni_red
            WHERE linija_id = v_linija_id
            LIMIT 1;
            
            IF v_vozilo_id IS NOT NULL THEN
                -- Zakaži izvanredni servis
                INSERT INTO odrzavanje_vozila (vozilo_id, zaposlenik_id, datum_servisa, vrsta_servisa, trosak_servisa, opis_radova)
                VALUES (v_vozilo_id, p_zaposlenik_id, DATE_ADD(v_datum_danas, INTERVAL 1 DAY), 'Izvanredni', 0.00, 
                        CONCAT('Planirano na temelju pritužbe #', p_prituzba_id));
            END IF;
        END IF;
        
        -- Notifikacija korisniku
        INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
        VALUES (
            v_korisnik_id,
            CASE 
                WHEN p_novi_status = 'Riješeno' THEN 'Info'
                WHEN p_novi_status = 'Odbačeno' THEN 'Upozorenje'
                ELSE 'Info'
            END,
            CONCAT('Pritužba #', p_prituzba_id, ' - ', p_novi_status),
            COALESCE(p_odgovor, CONCAT('Vaša pritužba je promijenila status u: ', p_novi_status))
        );
        
        -- Ažuriranje statistike (samo za nove pritužbe - kada se prvi put obrađuju)
        IF v_stari_status = 'Novo' THEN
            INSERT INTO statistika_sustava (datum, broj_prituzbi)
            VALUES (v_datum_danas, 1)
            ON DUPLICATE KEY UPDATE 
                broj_prituzbi = broj_prituzbi + 1;
        END IF;
        
        SET p_poruka = CONCAT('Pritužba #', p_prituzba_id, ' ažurirana na status: ', p_novi_status);
        COMMIT;
    END IF;
END //

-- ============================================================
-- PROCEDURA 6: GeneriranjeMjesecnogIzvjestaja
-- Opis: Procedura za generiranje mjesečnog izvještaja:
--       - Agregira sve podatke iz statistika
--       - Računa ukupne prihode i troškove
--       - Vraća detaljni izvještaj
--       - Kreira sumarnu notifikaciju za administratore
-- ============================================================
DROP PROCEDURE IF EXISTS GeneriranjeMjesecnogIzvjestaja //

CREATE PROCEDURE GeneriranjeMjesecnogIzvjestaja(
    IN p_godina INT,
    IN p_mjesec INT,
    OUT p_ukupno_karata INT,
    OUT p_ukupan_prihod DECIMAL(12,2),
    OUT p_ukupno_prekrsaja INT,
    OUT p_ukupno_kazni DECIMAL(12,2),
    OUT p_ukupno_servisa INT,
    OUT p_troskovi_servisa DECIMAL(12,2),
    OUT p_ukupno_prituzbi INT,
    OUT p_neto_rezultat DECIMAL(12,2),
    OUT p_poruka VARCHAR(500)
)
BEGIN
    DECLARE v_pocetni_datum DATE;
    DECLARE v_krajnji_datum DATE;
    DECLARE v_novi_korisnici INT;
    DECLARE v_aktivna_vozila INT;
    DECLARE v_vozila_na_servisu INT;
    DECLARE v_admin_korisnik_id INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom generiranja izvještaja.';
    END;
    
    START TRANSACTION;
    
    -- Postavljanje raspona datuma
    SET v_pocetni_datum = CONCAT(p_godina, '-', LPAD(p_mjesec, 2, '0'), '-01');
    SET v_krajnji_datum = LAST_DAY(v_pocetni_datum);
    
    -- Agregacija iz statistike sustava
    SELECT 
        COALESCE(SUM(ukupno_karata_prodano), 0),
        COALESCE(SUM(ukupan_prihod), 0),
        COALESCE(SUM(ukupno_prekrsaja), 0),
        COALESCE(SUM(ukupno_kazni), 0),
        COALESCE(SUM(broj_servisa), 0),
        COALESCE(SUM(troskovi_servisa), 0),
        COALESCE(SUM(broj_prituzbi), 0)
    INTO 
        p_ukupno_karata,
        p_ukupan_prihod,
        p_ukupno_prekrsaja,
        p_ukupno_kazni,
        p_ukupno_servisa,
        p_troskovi_servisa,
        p_ukupno_prituzbi
    FROM statistika_sustava
    WHERE datum BETWEEN v_pocetni_datum AND v_krajnji_datum;
    
    -- Izračun neto rezultata (prihodi - troškovi)
    SET p_neto_rezultat = (p_ukupan_prihod + p_ukupno_kazni) - p_troskovi_servisa;
    
    -- Dodatne statistike
    SELECT COUNT(*) INTO v_novi_korisnici
    FROM korisnici k
    JOIN karta ka ON k.id = ka.korisnik_id
    WHERE ka.datum_kupnje BETWEEN v_pocetni_datum AND v_krajnji_datum
    GROUP BY k.id
    HAVING MIN(ka.datum_kupnje) >= v_pocetni_datum;
    
    SET v_novi_korisnici = COALESCE(v_novi_korisnici, 0);
    
    -- Stanje vozila
    SELECT 
        SUM(CASE WHEN u_prometu = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN u_prometu = 0 THEN 1 ELSE 0 END)
    INTO v_aktivna_vozila, v_vozila_na_servisu
    FROM vozila;
    
    -- Pronađi prvog korisnika za notifikaciju (simulacija admin korisnika)
    SELECT MIN(id) INTO v_admin_korisnik_id FROM korisnici;
    
    -- Kreiranje izvještaja kao notifikacije
    IF v_admin_korisnik_id IS NOT NULL THEN
        INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
        VALUES (
            v_admin_korisnik_id,
            'Info',
            CONCAT('Mjesečni izvještaj ', p_mjesec, '/', p_godina),
            CONCAT(
                'PRIHODI: ', p_ukupan_prihod, ' EUR (', p_ukupno_karata, ' karata) | ',
                'KAZNE: ', p_ukupno_kazni, ' EUR (', p_ukupno_prekrsaja, ' prekršaja) | ',
                'TROŠKOVI: ', p_troskovi_servisa, ' EUR (', p_ukupno_servisa, ' servisa) | ',
                'NETO: ', p_neto_rezultat, ' EUR | ',
                'Pritužbi: ', p_ukupno_prituzbi
            )
        );
    END IF;
    
    -- Audit log za generiranje izvještaja
    INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
    VALUES (
        'izvjestaj',
        'INSERT',
        NULL,
        CONCAT('{"mjesec":', p_mjesec, ',"godina":', p_godina, ',"neto":', p_neto_rezultat, '}'),
        'SYSTEM'
    );
    
    SET p_poruka = CONCAT(
        'Izvještaj za ', p_mjesec, '/', p_godina, ' generiran. ',
        'Aktivna vozila: ', COALESCE(v_aktivna_vozila, 0), ', Na servisu: ', COALESCE(v_vozila_na_servisu, 0), '. ',
        'Neto rezultat: ', p_neto_rezultat, ' EUR'
    );
    
    COMMIT;
END //

-- ============================================================
-- PROCEDURA 7: RegistracijaNovogKorisnika
-- Opis: Procedura za registraciju novog korisnika:
--       - Automatski određuje kategoriju putnika prema dobi
--       - Provjerava duplikate email-a
--       - Kreira početnu notifikaciju dobrodošlice
--       - Bilježi u audit log
-- ============================================================
DROP PROCEDURE IF EXISTS RegistracijaNovogKorisnika //

CREATE PROCEDURE RegistracijaNovogKorisnika(
    IN p_ime VARCHAR(50),
    IN p_prezime VARCHAR(50),
    IN p_email VARCHAR(100),
    IN p_datum_rodenja DATE,
    OUT p_korisnik_id INT,
    OUT p_kategorija_naziv VARCHAR(50),
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_dob INT;
    DECLARE v_kategorija_id INT;
    DECLARE v_email_postoji INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom registracije korisnika.';
        SET p_korisnik_id = NULL;
    END;
    
    START TRANSACTION;
    
    -- Provjera duplikata email-a
    SELECT COUNT(*) INTO v_email_postoji
    FROM korisnici
    WHERE email = p_email;
    
    IF v_email_postoji > 0 THEN
        SET p_poruka = 'Greška: Email adresa već postoji u sustavu.';
        ROLLBACK;
    ELSE
        -- Izračun dobi
        SET v_dob = TIMESTAMPDIFF(YEAR, p_datum_rodenja, CURDATE());
        
        -- Automatsko određivanje kategorije prema dobi
        SELECT id, kategorija_naziv INTO v_kategorija_id, p_kategorija_naziv
        FROM kategorija_putnik
        WHERE v_dob >= min_dob AND v_dob <= max_dob
        ORDER BY postotak_popusta DESC
        LIMIT 1;
        
        -- Ako nije pronađena kategorija, uzmi default
        IF v_kategorija_id IS NULL THEN
            SELECT id, kategorija_naziv INTO v_kategorija_id, p_kategorija_naziv
            FROM kategorija_putnik
            LIMIT 1;
        END IF;
        
        -- Unos korisnika
        INSERT INTO korisnici (kategorija_id, ime, prezime, email, datum_rodenja, status_racuna)
        VALUES (v_kategorija_id, p_ime, p_prezime, p_email, p_datum_rodenja, 'Aktivan');
        
        SET p_korisnik_id = LAST_INSERT_ID();
        
        -- Notifikacija dobrodošlice
        INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
        VALUES (
            p_korisnik_id,
            'Info',
            'Dobrodošli u gradski prijevoz!',
            CONCAT('Poštovani/a ', p_ime, ' ', p_prezime, ', uspješno ste registrirani. ',
                   'Vaša kategorija: ', p_kategorija_naziv, '. Ugodna vožnja!')
        );
        
        -- Audit log
        INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
        VALUES (
            'korisnici',
            'INSERT',
            NULL,
            CONCAT('{"id":', p_korisnik_id, ',"ime":"', p_ime, '","prezime":"', p_prezime, '"}'),
            'SYSTEM_REGISTRATION'
        );
        
        SET p_poruka = CONCAT('Korisnik uspješno registriran. ID: ', p_korisnik_id, ', Kategorija: ', p_kategorija_naziv);
        COMMIT;
    END IF;
END //

-- ============================================================
-- PROCEDURA 8: AktivirajVoziloNakonServisa
-- Opis: Procedura za aktivaciju vozila nakon servisa:
--       - Provjerava je li servis završen
--       - Vraća vozilo u promet
--       - Automatski ga dodjeljuje prvoj dostupnoj liniji
--       - Bilježi sve promjene
-- ============================================================
DROP PROCEDURE IF EXISTS AktivirajVoziloNakonServisa //

CREATE PROCEDURE AktivirajVoziloNakonServisa(
    IN p_vozilo_id INT,
    IN p_zaposlenik_id INT,
    OUT p_dodijeljena_linija VARCHAR(100),
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_vozilo_postoji INT;
    DECLARE v_trenutno_u_prometu TINYINT;
    DECLARE v_tip_vozila VARCHAR(50);
    DECLARE v_reg_oznaka VARCHAR(10);
    DECLARE v_linija_id INT;
    DECLARE v_linija_naziv VARCHAR(100);
    DECLARE v_zadnji_servis DATE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom aktivacije vozila.';
    END;
    
    START TRANSACTION;
    
    -- Dohvat podataka o vozilu
    SELECT COUNT(*), u_prometu, tip_vozila, registarska_oznaka
    INTO v_vozilo_postoji, v_trenutno_u_prometu, v_tip_vozila, v_reg_oznaka
    FROM vozila
    WHERE id = p_vozilo_id
    GROUP BY u_prometu, tip_vozila, registarska_oznaka;
    
    IF v_vozilo_postoji = 0 THEN
        SET p_poruka = 'Greška: Vozilo ne postoji.';
        ROLLBACK;
    ELSEIF v_trenutno_u_prometu = 1 THEN
        SET p_poruka = 'Vozilo je već u prometu.';
        ROLLBACK;
    ELSE
        -- Provjeri zadnji servis
        SELECT MAX(datum_servisa) INTO v_zadnji_servis
        FROM odrzavanje_vozila
        WHERE vozilo_id = p_vozilo_id;
        
        -- Aktiviraj vozilo
        UPDATE vozila
        SET u_prometu = 1
        WHERE id = p_vozilo_id;
        
        -- Pronađi kompatibilnu liniju bez vozila
        SELECT l.id, l.naziv INTO v_linija_id, v_linija_naziv
        FROM linije l
        WHERE (
            (l.tip_linije = 'Tramvajska' AND v_tip_vozila = 'Tramvaj') OR
            (l.tip_linije = 'Autobusna' AND v_tip_vozila IN ('Autobus', 'Minibus', 'Kombi'))
        )
        AND l.id NOT IN (SELECT DISTINCT linija_id FROM vozni_red WHERE vozilo_id != p_vozilo_id)
        LIMIT 1;
        
        IF v_linija_id IS NOT NULL THEN
            SET p_dodijeljena_linija = v_linija_naziv;
        ELSE
            SET p_dodijeljena_linija = 'Nije dodijeljeno - nema slobodnih linija';
        END IF;
        
        -- Audit log
        INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
        VALUES (
            'vozila',
            'UPDATE',
            CONCAT('{"id":', p_vozilo_id, ',"u_prometu":0}'),
            CONCAT('{"id":', p_vozilo_id, ',"u_prometu":1,"zadnji_servis":"', COALESCE(v_zadnji_servis, 'N/A'), '"}'),
            CONCAT('zaposlenik_id:', p_zaposlenik_id)
        );
        
        SET p_poruka = CONCAT('Vozilo ', v_reg_oznaka, ' aktivirano. Linija: ', p_dodijeljena_linija);
        COMMIT;
    END IF;
END //

-- ============================================================
-- PROCEDURA 9: PlacanjeKazne
-- Opis: Procedura za plaćanje kazne:
--       - Ažurira status plaćanja prekršaja
--       - Automatski reaktivira korisnika ako je bio suspendiran
--       - Ažurira statistiku naplaćenih kazni
--       - Šalje potvrdu korisniku
-- ============================================================
DROP PROCEDURE IF EXISTS PlacanjeKazne //

CREATE PROCEDURE PlacanjeKazne(
    IN p_prekrsaj_id INT,
    IN p_iznos_uplacen DECIMAL(10,2),
    OUT p_korisnik_reaktiviran BOOLEAN,
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_korisnik_id INT;
    DECLARE v_iznos_kazne DECIMAL(10,2);
    DECLARE v_status_placanja VARCHAR(20);
    DECLARE v_status_korisnika VARCHAR(20);
    DECLARE v_preostalo_neplacenih INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom plaćanja kazne.';
        SET p_korisnik_reaktiviran = FALSE;
    END;
    
    START TRANSACTION;
    
    SET p_korisnik_reaktiviran = FALSE;
    
    -- Dohvat podataka o prekršaju
    SELECT korisnik_id, iznos_kazne, status_placanja
    INTO v_korisnik_id, v_iznos_kazne, v_status_placanja
    FROM prekrsaji
    WHERE id = p_prekrsaj_id;
    
    IF v_korisnik_id IS NULL THEN
        SET p_poruka = 'Greška: Prekršaj ne postoji.';
        ROLLBACK;
    ELSEIF v_status_placanja = 'Plaćeno' THEN
        SET p_poruka = 'Kazna je već plaćena.';
        ROLLBACK;
    ELSEIF p_iznos_uplacen < v_iznos_kazne THEN
        SET p_poruka = CONCAT('Greška: Nedovoljan iznos. Potrebno: ', v_iznos_kazne, ' EUR');
        ROLLBACK;
    ELSE
        -- Ažuriraj status prekršaja
        UPDATE prekrsaji
        SET status_placanja = 'Plaćeno'
        WHERE id = p_prekrsaj_id;
        
        -- Provjeri status korisnika
        SELECT status_racuna INTO v_status_korisnika
        FROM korisnici
        WHERE id = v_korisnik_id;
        
        -- Provjeri preostale neplaćene kazne
        SELECT COUNT(*) INTO v_preostalo_neplacenih
        FROM prekrsaji
        WHERE korisnik_id = v_korisnik_id AND status_placanja = 'Neplaćeno';
        
        -- Reaktivacija ako nema više neplaćenih i bio je suspendiran
        IF v_status_korisnika = 'Suspendiran' AND v_preostalo_neplacenih = 0 THEN
            UPDATE korisnici
            SET status_racuna = 'Aktivan'
            WHERE id = v_korisnik_id;
            
            SET p_korisnik_reaktiviran = TRUE;
            
            -- Notifikacija o reaktivaciji
            INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
            VALUES (
                v_korisnik_id,
                'Info',
                'Račun reaktiviran',
                'Sve kazne su podmirene. Vaš račun je ponovno aktivan. Hvala!'
            );
        END IF;
        
        -- Notifikacija o plaćanju
        INSERT INTO notifikacije (korisnik_id, tip_notifikacije, naslov, poruka)
        VALUES (
            v_korisnik_id,
            'Info',
            'Kazna plaćena',
            CONCAT('Kazna #', p_prekrsaj_id, ' u iznosu od ', v_iznos_kazne, ' EUR uspješno plaćena.')
        );
        
        IF p_korisnik_reaktiviran THEN
            SET p_poruka = CONCAT('Kazna plaćena. Korisnik reaktiviran - nema više dugovanja.');
        ELSE
            SET p_poruka = CONCAT('Kazna plaćena. Preostalo neplaćenih: ', v_preostalo_neplacenih);
        END IF;
        
        COMMIT;
    END IF;
END //

-- ============================================================
-- PROCEDURA 10: DodajStanicuNaLiniju
-- Opis: Procedura za dodavanje stanice na liniju:
--       - Provjerava postoji li linija i stanica
--       - Provjerava nije li stanica već na liniji
--       - Automatski računa redoslijed
--       - Pomiče ostale stanice ako se dodaje u sredinu
-- ============================================================
DROP PROCEDURE IF EXISTS DodajStanicuNaLiniju //

CREATE PROCEDURE DodajStanicuNaLiniju(
    IN p_linija_id INT,
    IN p_stanica_id INT,
    IN p_pozicija INT,
    OUT p_konacna_pozicija INT,
    OUT p_poruka VARCHAR(255)
)
BEGIN
    DECLARE v_linija_postoji INT;
    DECLARE v_stanica_postoji INT;
    DECLARE v_vec_na_liniji INT;
    DECLARE v_max_redoslijed INT;
    DECLARE v_linija_naziv VARCHAR(100);
    DECLARE v_stanica_naziv VARCHAR(100);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        SET p_poruka = 'Greška prilikom dodavanja stanice.';
    END;
    
    START TRANSACTION;
    
    -- Provjera linije
    SELECT COUNT(*), MAX(naziv) INTO v_linija_postoji, v_linija_naziv
    FROM linije WHERE id = p_linija_id;
    
    -- Provjera stanice
    SELECT COUNT(*), MAX(naziv) INTO v_stanica_postoji, v_stanica_naziv
    FROM stanice WHERE id = p_stanica_id;
    
    -- Je li već na liniji
    SELECT COUNT(*) INTO v_vec_na_liniji
    FROM linije_stanice
    WHERE linija_id = p_linija_id AND stanica_id = p_stanica_id;
    
    IF v_linija_postoji = 0 THEN
        SET p_poruka = 'Greška: Linija ne postoji.';
        ROLLBACK;
    ELSEIF v_stanica_postoji = 0 THEN
        SET p_poruka = 'Greška: Stanica ne postoji.';
        ROLLBACK;
    ELSEIF v_vec_na_liniji > 0 THEN
        SET p_poruka = 'Greška: Stanica je već na ovoj liniji.';
        ROLLBACK;
    ELSE
        -- Dohvat maksimalnog redoslijeda
        SELECT COALESCE(MAX(redoslijed), 0) INTO v_max_redoslijed
        FROM linije_stanice
        WHERE linija_id = p_linija_id;
        
        -- Određivanje pozicije
        IF p_pozicija IS NULL OR p_pozicija > v_max_redoslijed + 1 THEN
            SET p_konacna_pozicija = v_max_redoslijed + 1;
        ELSEIF p_pozicija < 1 THEN
            SET p_konacna_pozicija = 1;
        ELSE
            SET p_konacna_pozicija = p_pozicija;
            
            -- Pomakni ostale stanice
            UPDATE linije_stanice
            SET redoslijed = redoslijed + 1
            WHERE linija_id = p_linija_id AND redoslijed >= p_konacna_pozicija;
        END IF;
        
        -- Dodaj stanicu
        INSERT INTO linije_stanice (linija_id, stanica_id, redoslijed)
        VALUES (p_linija_id, p_stanica_id, p_konacna_pozicija);
        
        -- Audit log
        INSERT INTO audit_log (tablica_naziv, operacija, stari_podaci, novi_podaci, korisnik)
        VALUES (
            'linije_stanice',
            'INSERT',
            NULL,
            CONCAT('{"linija_id":', p_linija_id, ',"stanica_id":', p_stanica_id, ',"redoslijed":', p_konacna_pozicija, '}'),
            'SYSTEM'
        );
        
        SET p_poruka = CONCAT('Stanica "', v_stanica_naziv, '" dodana na liniju "', v_linija_naziv, '" na poziciju ', p_konacna_pozicija);
        COMMIT;
    END IF;
END //

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

DELIMITER ;

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