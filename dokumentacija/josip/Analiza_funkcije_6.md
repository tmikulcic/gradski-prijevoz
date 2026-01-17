# Analiza Funkcije 6

## Baza podataka: `gradski_prijevoz`

---

## FUNKCIJA 6: fn_izracunaj_staz_zaposlenika

### SQL kod:

```sql
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
```

### Opis SQL operacija:

Ova funkcija računa radni staž zaposlenika i vraća formatirani string s godinama, mjesecima i danima. Funkcija koristi:

• **RETURNS VARCHAR(100)** - funkcija vraća tekstualni rezultat (formatirani staž)

• **DETERMINISTIC** - označava da funkcija za iste ulazne parametre uvijek vraća isti rezultat

• **READS SQL DATA** - označava da funkcija čita podatke iz baze, ali ih ne mijenja

• **DECLARE** - deklaracija lokalnih varijabli:

- `v_datum_zaposlenja` - datum početka radnog odnosa
- `v_godine`, `v_mjeseci`, `v_dani` - komponente staža
- `v_ukupno_dana` - ukupan broj dana radnog staža
- `v_rezultat` - formatirani izlazni string

• **SELECT ... INTO** iz tablice `zaposlenik` - dohvaća datum zaposlenja za zadani ID zaposlenika

• **IF v_datum_zaposlenja IS NULL THEN RETURN NULL** - vraća NULL ako zaposlenik ne postoji u bazi

• **IF v_datum_zaposlenja > CURDATE()** - provjerava je li datum zaposlenja u budućnosti (osoba još nije počela raditi)

• **TIMESTAMPDIFF(YEAR, ...)** - MySQL funkcija koja računa razliku između dva datuma u godinama

• **TIMESTAMPDIFF(MONTH, ...)** - računa razliku u mjesecima, od koje se oduzimaju pune godine za dobivanje ostatka mjeseci

• **DATEDIFF(CURDATE(), v_datum_zaposlenja)** - računa ukupan broj dana između dva datuma

• **Korekcija negativnih dana** - matematička korekcija za slučajeve kad izračun dana daje negativnu vrijednost zbog aproksimacije (365 dana/godina, 30 dana/mjesec)

• **CONCAT(...)** - spaja sve komponente u formatirani string oblika "X god, Y mj, Z dana (ukupno N dana)"

### Korištene tablice:

| Tablica      | Operacija | Uloga                                    |
| ------------ | --------- | ---------------------------------------- |
| `zaposlenik` | SELECT    | Dohvaćanje datuma zaposlenja zaposlenika |

### Referencirani stupci:

| Tablica      | Stupac             | Opis                            |
| ------------ | ------------------ | ------------------------------- |
| `zaposlenik` | `id`               | Primarni ključ - ID zaposlenika |
| `zaposlenik` | `datum_zaposlenja` | Datum početka radnog odnosa     |

---

### Poslovni benefiti prikazanih informacija:

1. **Upravljanje ljudskim resursima**
   - Automatski izračun staža omogućuje HR odjelu brzi uvid u iskustvo zaposlenika bez ručnog računanja, što je korisno pri evaluacijama i planiranju.

2. **Izračun dodataka na plaću**
   - Mnoge tvrtke imaju dodatke na plaću bazirane na radnom stažu. Ova funkcija omogućuje automatizaciju takvih izračuna.

3. **Planiranje mirovina**
   - Praćenje staža je ključno za izračun prava na mirovinu i planiranje umirovljenja zaposlenika.

4. **Jubilarne nagrade**
   - Funkcija omogućuje lako prepoznavanje zaposlenika koji dostižu određene prekretnice (10, 20, 30 godina) za dodjelu jubileja.

5. **Prioriteti pri otpuštanju/napredovanju**
   - Pri restrukturiranju ili promocijama, staž je često jedan od kriterija. Funkcija pruža standardizirani izračun.

6. **Formatirani izlaz**
   - Vraćanje staža u čitljivom formatu ("5 god, 3 mj, 12 dana") olakšava prezentaciju u izvještajima i korisničkim sučeljima.

7. **Ukupan broj dana**
   - Dodatna informacija o ukupnom broju dana omogućuje precizne izračune za financijske i pravne potrebe.

8. **Validacija podataka**
   - Funkcija automatski obrađuje rubne slučajeve (nepostojeći zaposlenik, budući datum zaposlenja) vraćajući odgovarajuće vrijednosti.

---

## Korištene MySQL funkcije:

| Funkcija                            | Opis                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------- |
| `TIMESTAMPDIFF(unit, date1, date2)` | Računa razliku između dva datuma u zadanoj jedinici (YEAR, MONTH, DAY...) |
| `DATEDIFF(date1, date2)`            | Vraća razliku u danima između dva datuma                                  |
| `CURDATE()`                         | Vraća trenutni datum (bez vremena)                                        |
| `CONCAT(str1, str2, ...)`           | Spaja stringove u jedan                                                   |

---

## Primjeri korištenja:

### Dohvat staža jednog zaposlenika:

```sql
SELECT fn_izracunaj_staz_zaposlenika(1) AS radni_staz;
-- Rezultat: "5 god, 3 mj, 12 dana (ukupno 1928 dana)"
```

### Kombinacija s podacima zaposlenika:

```sql
SELECT
    z.id,
    CONCAT(z.ime, ' ', z.prezime) AS ime_prezime,
    z.naziv_uloge,
    z.datum_zaposlenja,
    fn_izracunaj_staz_zaposlenika(z.id) AS radni_staz
FROM zaposlenik z
ORDER BY z.datum_zaposlenja ASC;
```

### Pronalazak zaposlenika s više od 10 godina staža:

```sql
SELECT
    z.id,
    CONCAT(z.ime, ' ', z.prezime) AS ime_prezime,
    fn_izracunaj_staz_zaposlenika(z.id) AS radni_staz
FROM zaposlenik z
WHERE TIMESTAMPDIFF(YEAR, z.datum_zaposlenja, CURDATE()) >= 10;
```

### Nepostojeći zaposlenik:

```sql
SELECT fn_izracunaj_staz_zaposlenika(9999) AS radni_staz;
-- Rezultat: NULL
```

### Zaposlenik s budućim datumom zaposlenja:

```sql
SELECT fn_izracunaj_staz_zaposlenika(100) AS radni_staz;
-- Rezultat: "Još nije započeo radni odnos"
```

---

## Povezanost s ostalim funkcijama:

| Funkcija                        | Opis                            | Veza s fn_izracunaj_staz_zaposlenika |
| ------------------------------- | ------------------------------- | ------------------------------------ |
| `fn_izracunaj_cijenu_karte`     | Računa cijenu karte s popustima | Nema direktne veze                   |
| `fn_provjeri_valjanost_karte`   | Provjerava status karte         | Nema direktne veze                   |
| `fn_odredi_kategoriju_po_dobi`  | Određuje kategoriju prema dobi  | Slična logika izračuna vremena       |
| `fn_broj_stanica_izmedu`        | Računa udaljenost stanica       | Nema direktne veze                   |
| `fn_provjeri_dostupnost_vozila` | Provjerava dostupnost vozila    | Koristi se za vozače (zaposlenike)   |

Funkcija `fn_izracunaj_staz_zaposlenika` je samostalna HR funkcija koja se može koristiti u kombinaciji s `fn_provjeri_dostupnost_vozila` za analizu iskustva vozača prilikom raspoređivanja na linije.
