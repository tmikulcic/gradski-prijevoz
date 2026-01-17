# Analiza View-a 6

## Baza podataka: `gradski_prijevoz`

---

## VIEW 6: vw_neplacene_kazne_pregled

### SQL kod:

```sql
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
```

### Opis SQL operacija:

Ovaj view pruža kompletan pregled svih neplaćenih kazni s detaljnim informacijama o korisnicima i kontrolorima. View koristi:

• **SELECT s aliasima** - svaki stupac ima čitljiv alias za lakše korištenje u aplikacijama i izvještajima

• **CONCAT(k.ime, ' ', k.prezime)** - spaja ime i prezime korisnika u jedan stupac `korisnik_ime`

• **CONCAT(z.ime, ' ', z.prezime)** - spaja ime i prezime kontrolora koji je evidentirao prekršaj

• **JOIN korisnici k ON p.korisnik_id = k.id** - spaja prekršaje s podacima o korisnicima

• **JOIN zaposlenik z ON p.zaposlenik_id = z.id** - spaja prekršaje s podacima o zaposleniku (kontroloru)

• **DATEDIFF(CURDATE(), DATE(p.datum_prekrsaja))** - računa broj dana od prekršaja do danas (koliko dugo je kazna neplaćena)

• **CASE WHEN ... THEN ... ELSE ... END** - kategorizira kazne po prioritetu naplate:

- `> 90 dana` → "Kritično (>90 dana)"
- `> 30 dana` → "Upozorenje (>30 dana)"
- `<= 30 dana` → "Novo (<30 dana)"

• **Korelirani podupit za COUNT(\*)** - broji ukupan broj neplaćenih prekršaja za svakog korisnika

• **Korelirani podupit za SUM(iznos_kazne)** - računa ukupno dugovanje korisnika iz svih neplaćenih kazni

• **WHERE p.status_placanja = 'Neplaćeno'** - filtrira samo neplaćene kazne

• **ORDER BY dana_neplaceno DESC, p.iznos_kazne DESC** - sortira po starosti kazne (najstarije prvo), zatim po iznosu (najveće prvo)

### Korištene tablice:

| Tablica      | Tip spoja | Uloga                                            |
| ------------ | --------- | ------------------------------------------------ |
| `prekrsaji`  | Glavna    | Izvorni podaci o prekršajima i kaznama           |
| `korisnici`  | JOIN      | Podaci o korisniku koji je počinio prekršaj      |
| `zaposlenik` | JOIN      | Podaci o kontroloru koji je evidentirao prekršaj |

### Referencirani stupci:

| Tablica      | Stupac            | Opis                                |
| ------------ | ----------------- | ----------------------------------- |
| `prekrsaji`  | `id`              | Primarni ključ prekršaja            |
| `prekrsaji`  | `datum_prekrsaja` | Datum i vrijeme evidentiranja       |
| `prekrsaji`  | `iznos_kazne`     | Iznos kazne u EUR                   |
| `prekrsaji`  | `status_placanja` | Status plaćanja (Neplaćeno/Plaćeno) |
| `prekrsaji`  | `napomena`        | Opis prekršaja                      |
| `prekrsaji`  | `korisnik_id`     | FK na korisnika                     |
| `prekrsaji`  | `zaposlenik_id`   | FK na zaposlenika (kontrolora)      |
| `korisnici`  | `id`              | Primarni ključ korisnika            |
| `korisnici`  | `ime`             | Ime korisnika                       |
| `korisnici`  | `prezime`         | Prezime korisnika                   |
| `korisnici`  | `email`           | Email adresa korisnika              |
| `korisnici`  | `status_racuna`   | Status računa (Aktivan/Suspendiran) |
| `zaposlenik` | `id`              | Primarni ključ zaposlenika          |
| `zaposlenik` | `ime`             | Ime kontrolora                      |
| `zaposlenik` | `prezime`         | Prezime kontrolora                  |
| `zaposlenik` | `zaposlenik_broj` | Službeni broj zaposlenika           |

---

### Poslovni benefiti prikazanih informacija:

1. **Upravljanje naplatom dugovanja**
   - Centralizirani pregled svih neplaćenih kazni omogućuje odjelu naplate efikasno praćenje i prioritizaciju aktivnosti.

2. **Prioritizacija po starosti duga**
   - Automatska kategorizacija (Kritično/Upozorenje/Novo) omogućuje fokusiranje na najstarije dugove koji imaju najveći rizik nenaplativosti.

3. **Kontakt informacije**
   - Email korisnika omogućuje slanje automatiziranih opomena bez ručnog pretraživanja podataka.

4. **Identifikacija problematičnih korisnika**
   - Stupci `ukupno_neplacenih_korisnik` i `ukupno_dugovanje_korisnik` identificiraju korisnike s višestrukim prekršajima za poseban tretman.

5. **Praćenje kontrolora**
   - Podaci o kontroloru omogućuju analizu učinkovitosti pojedinih kontrolora i potencijalnu validaciju spornih prekršaja.

6. **Status korisnika**
   - Informacija o statusu računa (Aktivan/Suspendiran) pomaže u odluci o daljnjim mjerama (suspenzija se može automatski primijeniti nakon određenog broja neplaćenih kazni).

7. **Pravna zaštita**
   - Datum prekršaja i napomena služe kao dokaz u slučaju pravnih postupaka za naplatu.

8. **Financijsko planiranje**
   - Ukupni pregled neplaćenih dugovanja pomaže u planiranju prihoda i procjeni nenaplativih potraživanja.

9. **Automatizacija opomena**
   - View se može koristiti kao izvor za automatske email opomene (sve kazne starije od 30 dana) ili SMS upozorenja.

---

## Izlazni stupci:

| Stupac                       | Tip podatka | Opis                                    |
| ---------------------------- | ----------- | --------------------------------------- |
| `prekrsaj_id`                | INT         | Jedinstveni ID prekršaja                |
| `datum_prekrsaja`            | DATETIME    | Datum i vrijeme evidentiranja prekršaja |
| `iznos_kazne`                | DECIMAL     | Iznos kazne u EUR                       |
| `status_placanja`            | VARCHAR     | Uvijek 'Neplaćeno' (filtrirano)         |
| `napomena`                   | TEXT        | Opis prekršaja                          |
| `korisnik_id`                | INT         | ID korisnika                            |
| `korisnik_ime`               | VARCHAR     | Puno ime korisnika                      |
| `korisnik_email`             | VARCHAR     | Email adresa za kontakt                 |
| `status_korisnika`           | VARCHAR     | Status računa korisnika                 |
| `kontrolor`                  | VARCHAR     | Puno ime kontrolora                     |
| `kontrolor_broj`             | VARCHAR     | Službeni broj kontrolora                |
| `dana_neplaceno`             | INT         | Broj dana od prekršaja                  |
| `prioritet_naplate`          | VARCHAR     | Kategorija prioriteta                   |
| `ukupno_neplacenih_korisnik` | INT         | Ukupan broj neplaćenih kazni korisnika  |
| `ukupno_dugovanje_korisnik`  | DECIMAL     | Ukupno dugovanje korisnika              |

---

## Primjeri korištenja:

### Dohvat svih neplaćenih kazni:

```sql
SELECT * FROM vw_neplacene_kazne_pregled;
```

### Samo kritične kazne (starije od 90 dana):

```sql
SELECT
    korisnik_ime,
    korisnik_email,
    iznos_kazne,
    dana_neplaceno
FROM vw_neplacene_kazne_pregled
WHERE prioritet_naplate = 'Kritično (>90 dana)';
```

### Korisnici s više od 3 neplaćene kazne:

```sql
SELECT DISTINCT
    korisnik_id,
    korisnik_ime,
    korisnik_email,
    ukupno_neplacenih_korisnik,
    ukupno_dugovanje_korisnik
FROM vw_neplacene_kazne_pregled
WHERE ukupno_neplacenih_korisnik >= 3
ORDER BY ukupno_dugovanje_korisnik DESC;
```

### Ukupna statistika neplaćenih kazni:

```sql
SELECT
    prioritet_naplate,
    COUNT(*) AS broj_kazni,
    SUM(iznos_kazne) AS ukupan_iznos,
    AVG(iznos_kazne) AS prosjecni_iznos
FROM vw_neplacene_kazne_pregled
GROUP BY prioritet_naplate
ORDER BY
    CASE prioritet_naplate
        WHEN 'Kritično (>90 dana)' THEN 1
        WHEN 'Upozorenje (>30 dana)' THEN 2
        ELSE 3
    END;
```

### Lista za email opomene:

```sql
SELECT
    korisnik_email,
    korisnik_ime,
    iznos_kazne,
    dana_neplaceno,
    napomena
FROM vw_neplacene_kazne_pregled
WHERE dana_neplaceno >= 30
  AND korisnik_email IS NOT NULL
ORDER BY korisnik_email, dana_neplaceno DESC;
```

### Produktivnost kontrolora:

```sql
SELECT
    kontrolor,
    kontrolor_broj,
    COUNT(*) AS broj_evidentiranih_prekrsaja,
    SUM(iznos_kazne) AS ukupna_vrijednost
FROM vw_neplacene_kazne_pregled
GROUP BY kontrolor, kontrolor_broj
ORDER BY broj_evidentiranih_prekrsaja DESC;
```

---

## Povezanost s ostalim view-ovima:

| View                     | Opis                | Veza s vw_neplacene_kazne_pregled                  |
| ------------------------ | ------------------- | -------------------------------------------------- |
| `vw_korisnici_pregled`   | Dashboard korisnika | Sadrži agregirane podatke o neplaćenim prekršajima |
| `vw_vozila_status`       | Status vozila       | Nema direktne veze                                 |
| `vw_linije_sa_stanicama` | Pregled linija      | Nema direktne veze                                 |
| `vw_dnevna_statistika`   | Dnevna statistika   | Sadrži dnevne prihode od kazni                     |
| `vw_vozni_red_detalji`   | Vozni red           | Nema direktne veze                                 |

View `vw_neplacene_kazne_pregled` se može koristiti u kombinaciji s `vw_korisnici_pregled` za potpuni pregled korisnika s dugovima, ili s `vw_dnevna_statistika` za analizu trenda prekršaja.
