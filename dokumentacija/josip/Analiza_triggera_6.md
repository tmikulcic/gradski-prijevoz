# Analiza Triggera 6

## Baza podataka: `gradski_prijevoz`

---

## TRIGGER 6: trg_vozni_red_before_insert (Validacija voznog reda)

### SQL kod:

```sql
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
```

### Opis SQL operacija:

Ovaj trigger se aktivira **BEFORE INSERT** na tablicu `vozni_red`, što znači da se izvršava prije nego što se novi zapis upiše u bazu. Trigger koristi:

• **DECLARE** - deklaracija lokalnih varijabli za pohranu privremenih vrijednosti:

- `v_vozilo_u_prometu` - status vozila (1 = u prometu, 0 = nije)
- `v_tip_vozila` - tip vozila (Tramvaj, Autobus, Minibus, Kombi)
- `v_tip_linije` - tip linije (Tramvajska, Autobusna, Uspinjača, Žičara)
- `v_konflikt` - brojač konflikata u rasporedu
- `v_kompatibilno` - boolean za provjeru kompatibilnosti

• **SELECT ... INTO** iz tablice `vozila` - dohvaća status prometa i tip vozila za vozilo koje se pokušava rasporediti

• **SELECT ... INTO** iz tablice `linije` - dohvaća tip linije na koju se vozilo raspoređuje

• **IF ... THEN SIGNAL SQLSTATE '45000'** - baca korisničku grešku ako vozilo nije u prometu, čime se prekida INSERT operacija

• **CASE WHEN ... THEN ... ELSE ... END** - logička provjera kompatibilnosti tipa vozila s tipom linije:

- Tramvaj → samo Tramvajska linija
- Autobus, Minibus, Kombi → samo Autobusna linija
- Uspinjača i Žičara → uvijek kompatibilni

• **SELECT COUNT(\*) INTO v_konflikt** iz tablice `vozni_red` - broji postojeće rasporede koji bi se vremenski preklapali:

- Uvjet `ABS(TIME_TO_SEC(TIMEDIFF(...))) < 1800` provjerava je li razlika manja od 30 minuta (1800 sekundi)
- Provjerava se i za vozilo i za vozača zasebno
- Dodatni uvjet `kalendar_id = NEW.kalendar_id` osigurava provjeru samo za isti tip dana

• **SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT** - MySQL mehanizam za bacanje korisničkih grešaka s opisnom porukom

### Korištene tablice:

| Tablica     | Operacija | Uloga                                              |
| ----------- | --------- | -------------------------------------------------- |
| `vozni_red` | INSERT    | Ciljna tablica triggera - raspored vožnji          |
| `vozila`    | SELECT    | Dohvaćanje statusa i tipa vozila                   |
| `linije`    | SELECT    | Dohvaćanje tipa linije za provjeru kompatibilnosti |

### Referencirani stupci:

| Tablica     | Stupac            | Opis                                   |
| ----------- | ----------------- | -------------------------------------- |
| `vozni_red` | `vozilo_id`       | ID vozila u rasporedu                  |
| `vozni_red` | `linija_id`       | ID linije u rasporedu                  |
| `vozni_red` | `vozac_id`        | ID vozača u rasporedu                  |
| `vozni_red` | `kalendar_id`     | ID kalendara (radni dan, vikend...)    |
| `vozni_red` | `vrijeme_polaska` | Vrijeme polaska vožnje                 |
| `vozila`    | `u_prometu`       | Status vozila (1=aktivno, 0=neaktivno) |
| `vozila`    | `tip_vozila`      | Tip vozila (Tramvaj, Autobus...)       |
| `linije`    | `tip_linije`      | Tip linije (Tramvajska, Autobusna...)  |

---

### Poslovni benefiti prikazanih informacija:

1. **Sprječavanje operativnih grešaka**
   - Trigger automatski blokira raspoređivanje vozila koja nisu u prometu (na servisu ili u kvaru), što sprječava planiranje vožnji s neispravnim vozilima i izbjegava iznenadne prekide usluge.

2. **Osiguranje kompatibilnosti vozila i linije**
   - Automatska validacija osigurava da tramvaji voze samo tramvajske linije, a autobusi autobusne. Ovo eliminira ljudske pogreške pri unosu podataka i održava operativni integritet sustava.

3. **Eliminacija vremenskih konflikata vozila**
   - Provjera ±30 minuta sprječava da isto vozilo bude raspoređeno na dvije vožnje istovremeno ili u prekratkom razmaku, što bi bilo fizički nemoguće izvesti.

4. **Eliminacija vremenskih konflikata vozača**
   - Ista logika štiti od prekomjernog opterećenja vozača i osigurava da jedan vozač ne bude raspoređen na dvije vožnje istovremeno.

5. **Proaktivna validacija podataka**
   - Budući da je trigger tipa BEFORE INSERT, podaci se validiraju prije upisa u bazu. Ovo je efikasnije od naknadne provjere jer spriječava upis neispravnih podataka.

6. **Jasne poruke o greškama**
   - Korištenje SIGNAL s prilagođenim MESSAGE_TEXT omogućuje precizne povratne informacije o razlogu odbijanja unosa, što olakšava ispravljanje grešaka.

7. **Automatizacija poslovnih pravila**
   - Poslovna pravila o kompatibilnosti i raspoređivanju implementirana su na razini baze podataka, što znači da vrijede neovisno o aplikaciji koja pristupa bazi.

8. **Smanjenje ručnog nadzora**
   - Automatska validacija smanjuje potrebu za ručnom provjerom rasporeda, čime se štedi vrijeme administratora i smanjuje rizik od previđenih konflikata.

---

## Usporedba s PROCEDUROM 11 (KreirajVozniRed)

| Aspekt                   | Trigger 6                      | Procedura 11                        |
| ------------------------ | ------------------------------ | ----------------------------------- |
| **Tip**                  | BEFORE INSERT trigger          | Stored procedure                    |
| **Aktivacija**           | Automatski pri svakom INSERT-u | Eksplicitni poziv (CALL)            |
| **Validacija kalendara** | Ne provjerava                  | Provjerava postojanje kalendara     |
| **Audit log**            | Ne bilježi                     | Bilježi u audit_log tablicu         |
| **Transakcije**          | Unutar INSERT transakcije      | Vlastita transakcija (START/COMMIT) |
| **Povratna informacija** | SIGNAL error                   | OUT parametar s porukom             |
| **Fleksibilnost**        | Uvijek se aktivira             | Može se zaobići direktnim INSERT-om |

Trigger 6 i Procedura 11 imaju sličnu logiku validacije, ali služe različitim svrhama:

- **Trigger** osigurava integritet podataka na razini baze neovisno o načinu unosa
- **Procedura** pruža kontrolirano sučelje s dodatnim funkcionalnostima (audit log, transakcije)

---

## Primjer korištenja:

### Uspješan unos:

```sql
-- Vozilo ID 1 (Tramvaj, u prometu) na liniju ID 1 (Tramvajska)
INSERT INTO vozni_red (linija_id, vozilo_id, vozac_id, kalendar_id, vrijeme_polaska)
VALUES (1, 1, 1, 1, '08:00:00');
-- Rezultat: Uspješno uneseno
```

### Neuspješan unos - vozilo nije u prometu:

```sql
-- Vozilo ID 5 je na servisu (u_prometu = 0)
INSERT INTO vozni_red (linija_id, vozilo_id, vozac_id, kalendar_id, vrijeme_polaska)
VALUES (1, 5, 1, 1, '09:00:00');
-- Rezultat: ERROR 1644 (45000): Greška: Vozilo nije u prometu (servis/kvar). Odaberite drugo vozilo.
```

### Neuspješan unos - nekompatibilno vozilo:

```sql
-- Autobus (ID 3) na tramvajsku liniju (ID 1)
INSERT INTO vozni_red (linija_id, vozilo_id, vozac_id, kalendar_id, vrijeme_polaska)
VALUES (1, 3, 1, 1, '10:00:00');
-- Rezultat: ERROR 1644 (45000): Greška: Tip vozila nije kompatibilan s tipom linije.
```

### Neuspješan unos - konflikt rasporeda:

```sql
-- Isto vozilo već ima vožnju u 08:00, novi unos u 08:15 (unutar 30 min)
INSERT INTO vozni_red (linija_id, vozilo_id, vozac_id, kalendar_id, vrijeme_polaska)
VALUES (2, 1, 2, 1, '08:15:00');
-- Rezultat: ERROR 1644 (45000): Greška: Vozilo je već raspoređeno u tom vremenskom periodu (±30 min).
```
