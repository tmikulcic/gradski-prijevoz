# ANALIZA PROCEDURA 11 I 12

## Baza podataka: gradski_prijevoz

---

## PROCEDURA 11: KreirajVozniRed

### SQL kod:

```sql
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
```

Ova procedura kreira novi zapis u voznom redu s potpunom validacijom poslovnih pravila. Procedura koristi:

• **SELECT** iz tablice `linije` dohvaća tip linije (`tip_linije`) kako bi se provjerila kompatibilnost s vozilom;

• **SELECT** iz tablice `vozila` dohvaća tip vozila (`tip_vozila`) i status prometa (`u_prometu`) radi provjere dostupnosti vozila;

• **SELECT** iz tablice `zaposlenik` dohvaća ulogu vozača (`naziv_uloge`) za validaciju postojanja zaposlenika;

• **SELECT COUNT(\*)** iz tablice `kalendari` provjerava postoji li traženi kalendar u sustavu;

• **SELECT COUNT(\*)** iz tablice `vozni_red` s uvjetom `ABS(TIME_TO_SEC(TIMEDIFF(vrijeme_polaska, p_vrijeme_polaska))) < 1800` detektira vremenske konflikte (±30 minuta) za vozilo i vozača zasebno;

• Funkcija **CASE** određuje kompatibilnost tipa vozila s tipom linije prema poslovnim pravilima:

- Tramvaj može voziti samo na Tramvajskoj liniji
- Autobus, Minibus i Kombi mogu voziti na Autobusnoj liniji
- Uspinjača i Žičara su uvijek kompatibilne

• **INSERT** u tablicu `vozni_red` unosi novi raspored vožnje s podacima o liniji, vozilu, vozaču, kalendaru i vremenu polaska;

• **INSERT** u tablicu `audit_log` bilježi promjenu u JSON formatu za reviziju i praćenje.

Procedura koristi **START TRANSACTION** za atomarnost operacija, s **ROLLBACK** pri bilo kojoj validacijskoj pogrešci i **COMMIT** samo ako sve provjere uspiju. **EXIT HANDLER FOR SQLEXCEPTION** hvata neočekivane greške i poništava transakciju.

### Poslovni benefiti prikazanih informacija

• **Sprječavanje nekompatibilnih rasporeda**

- Osigurava da tramvaji voze samo tramvajske linije, a autobusi autobusne, čime se eliminiraju operativne greške u planiranju prometovanja.

• **Optimizacija raspoloživosti voznog parka**

- Automatska provjera statusa vozila (`u_prometu`) sprječava raspoređivanje vozila koja su na servisu ili u kvaru, što povećava pouzdanost usluge.

• **Eliminacija vremenskih konflikata**

- Provjera ±30 minuta za vozilo i vozača osigurava da isti resurs nije dvostruko rezerviran, što poboljšava pouzdanost i točnost voznog reda.

• **Potpuna revizijska staza**

- Bilježenje u `audit_log` omogućuje praćenje tko je, kada i što promijenio u voznom redu, što je ključno za odgovornost i analizu problema.

• **Integritet podataka**

- Transakcijska logika garantira da se podaci unesu u cijelosti ili uopće ne, sprječavajući djelomične ili nekonzistentne unose u bazu.

• **Validacija kalendara**

- Provjera postojanja kalendara osigurava da se rasporedi kreiraju samo za definirane radne dane, vikende ili posebne dane.

---

## PROCEDURA 12: ArhivirajStareKarte

### SQL kod:

```sql
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
```

Ova procedura provodi arhiviranje i čišćenje starih karata iz baze podataka radi optimizacije performansi i održavanja sustava. Procedura koristi:

• Funkcija **DATE_SUB(CURDATE(), INTERVAL p_starije_od_dana DAY)** izračunava granični datum za arhiviranje na temelju ulaznog parametra koji definira starost karata u danima;

• **SELECT** iz tablice `karta` s agregatnim funkcijama:

- **COUNT(\*)** broji ukupan broj karata za brisanje
- **SUM(placena_cijena)** zbraja ukupnu vrijednost karata koje će biti obrisane
- **MIN(DATE(datum_kupnje))** i **MAX(DATE(datum_kupnje))** određuju vremenski raspon obuhvaćenih karata

• Uvjet **WHERE vrijedi_do < v_datum_granica** filtrira samo karte kojima je istekla valjanost prije graničnog datuma;

• **INSERT** u tablicu `audit_log` prije brisanja bilježi sumarnu statistiku u JSON formatu (broj karata, ukupna vrijednost, vremenski period) za reviziju i mogućnost rekonstrukcije podataka;

• **DELETE FROM karta** briše sve karte koje zadovoljavaju uvjet starosti, oslobađajući prostor u bazi.

Procedura koristi **START TRANSACTION** za atomarnost operacija, s **ROLLBACK** pri greški i **COMMIT** nakon uspješnog arhiviranja. Funkcija **COALESCE** osigurava da se NULL vrijednosti zamijene s 0 kod zbrajanja.

### Poslovni benefiti prikazanih informacija

• **Optimizacija performansi baze podataka**

- Redovito brisanje starih karata smanjuje veličinu tablice, što ubrzava upite i smanjuje vrijeme odziva sustava za krajnje korisnike.

• **Upravljanje pohranom**

- Automatsko čišćenje nepotrebnih podataka smanjuje troškove pohrane i održava bazu u optimalnom stanju.

• **Potpuna revizijska staza prije brisanja**

- Bilježenje sumarnih podataka u `audit_log` prije brisanja omogućuje rekonstrukciju povijesnih statistika i zadovoljava regulatorne zahtjeve o čuvanju zapisa.

• **Transparentnost operacija**

- Izlazni parametri vraćaju broj obrisanih karata i ukupnu vrijednost, što omogućuje administratorima praćenje učinka arhiviranja.

• **Fleksibilnost konfiguracije**

- Ulazni parametar `p_starije_od_dana` omogućuje prilagodbu politike zadržavanja podataka prema poslovnim potrebama (npr. 365 dana za godišnje arhiviranje).

• **Sigurnost podataka**

- Transakcijska logika osigurava da se brisanje provede u cijelosti ili uopće ne, sprječavajući djelomično brisanje koje bi moglo narušiti integritet podataka.

• **Automatizacija održavanja**

- Procedura se može zakazati kao redoviti posao (scheduled job) za automatsko održavanje baze bez ručne intervencije.

---

## PRIMJERI POZIVA

### Procedura 11 - KreirajVozniRed

```sql
CALL KreirajVozniRed(1, 1, 1, 1, '08:00:00', @id, @poruka);
SELECT @id AS vozni_red_id, @poruka AS poruka;
```

### Procedura 12 - ArhivirajStareKarte

```sql
CALL ArhivirajStareKarte(365, @obrisano, @vrijednost, @poruka);
SELECT @obrisano AS broj_obrisanih, @vrijednost AS ukupna_vrijednost, @poruka AS poruka;
```

---

## KORIŠTENE TABLICE

| Procedura           | Tablica    | Operacija      |
| ------------------- | ---------- | -------------- |
| KreirajVozniRed     | linije     | SELECT         |
| KreirajVozniRed     | vozila     | SELECT         |
| KreirajVozniRed     | zaposlenik | SELECT         |
| KreirajVozniRed     | kalendari  | SELECT         |
| KreirajVozniRed     | vozni_red  | SELECT, INSERT |
| KreirajVozniRed     | audit_log  | INSERT         |
| ArhivirajStareKarte | karta      | SELECT, DELETE |
| ArhivirajStareKarte | audit_log  | INSERT         |
