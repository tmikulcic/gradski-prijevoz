# Analiza složenih SQL upita 16, 17 i 18

## Baza podataka: `gradski_prijevoz`

---

## UPIT 16: Stanice koje povezuju najviše linija

### SQL kod:

```sql
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
```

### Opis SQL operacija:

- **SELECT s višestrukim stupcima** - dohvaća ID stanice, naziv, zonu i izračunate vrijednosti
- **COUNT(DISTINCT ls.linija_id)** - broji jedinstvene linije koje prolaze kroz stanicu
- **GROUP_CONCAT(DISTINCT ... ORDER BY ... SEPARATOR)** - spaja oznake svih linija u jedan string, sortirano i odvojeno zarezom
- **Korelirani podupiti** - dva podupit za brojanje tramvajskih i autobusnih linija zasebno:
  - Prvi podupit filtrira po `tip_linije = 'Tramvajska'`
  - Drugi podupit filtrira po `tip_linije = 'Autobusna'`
- **INNER JOIN zone z ON s.zona_id = z.id** - spaja tablicu stanica sa zonama
- **LEFT JOIN linije_stanice ls** - spaja sa međutablicom (LEFT jer želimo sve stanice)
- **LEFT JOIN linije l** - spaja s tablicama linija
- **GROUP BY s.id, s.naziv, z.zona_naziv** - grupira rezultate po stanici
- **HAVING COUNT(...) > 0** - filtrira samo stanice koje imaju barem jednu liniju
- **ORDER BY broj_linija DESC** - sortira silazno po broju linija
- **LIMIT 10** - vraća samo 10 stanica s najviše linija

### Korištene tablice:

| Tablica          | Uloga                                      |
| ---------------- | ------------------------------------------ |
| `stanice`        | Glavna tablica - podaci o stanicama        |
| `zone`           | Informacije o zonama za svaku stanicu      |
| `linije_stanice` | Međutablica koja povezuje linije i stanice |
| `linije`         | Podaci o linijama (oznaka, tip, naziv)     |

### Poslovni benefiti prikazanih informacija:

1. **Identifikacija prometnih čvorišta** - Stanice s najviše linija su ključne točke mreže gdje se susreću putnici s različitih linija, što omogućuje bolju alokaciju resursa
2. **Planiranje infrastrukture** - Čvorišne stanice trebaju veće kapacitete, više natkrija, bolje oznake i informacijske table
3. **Optimizacija presjedanja** - Znanje o broju linija na stanici pomaže u kreiranju boljih voznih redova za minimiziranje vremena čekanja pri presjedanju
4. **Razlikovanje tramvaj vs autobus** - Informacija o tipu prijevoza pomaže u planiranju intermodalnog prometa
5. **Marketing i oglašavanje** - Stanice s najviše prometa su najvrjednija mjesta za oglašavanje
6. **Sigurnost putnika** - Prometnije stanice zahtijevaju veći nadzor i sigurnosne mjere

---

## UPIT 17: Analiza prihoda po mjesecima

### SQL kod:

```sql
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
            DATE_FORMAT(ka.datum_kupnje, '%Y-%m') AS mjesec,
            COUNT(ka.id) AS broj_prodanih_karata,
            COUNT(DISTINCT ka.korisnik_id) AS broj_razlicitih_kupaca,
            ROUND(SUM(ka.placena_cijena), 2) AS ukupni_prihod,
            ROUND(AVG(ka.placena_cijena), 2) AS prosjecna_cijena
        FROM karta ka
        GROUP BY
            DATE_FORMAT(ka.datum_kupnje, '%Y-%m')
    ) AS mjesec_grupa
ORDER BY mjesec_grupa.mjesec DESC;
```

### Opis SQL operacija:

- **Derived table (podupit u FROM)** - kreira virtualnu tablicu `mjesec_grupa` s agregiranim podacima:
  - `DATE_FORMAT(ka.datum_kupnje, '%Y-%m')` - formatira datum u YYYY-MM oblik za grupiranje po mjesecu
  - `COUNT(ka.id)` - broji prodane karte
  - `COUNT(DISTINCT ka.korisnik_id)` - broji jedinstvene kupce
  - `SUM(ka.placena_cijena)` - sumira ukupni prihod
  - `AVG(ka.placena_cijena)` - računa prosječnu cijenu karte
  - `ROUND(..., 2)` - zaokružuje na 2 decimale
- **Korelirani podupit za najpopularniji tip karte**:
  - Grupira karte po tipu za određeni mjesec
  - `ORDER BY COUNT(*) DESC LIMIT 1` - vraća tip s najviše prodaja
- **Korelirani podupit za prekršaje** - broji prekršaje u istom mjesecu za usporedbu
- **ORDER BY mjesec DESC** - sortira od najnovijeg prema najstarijem mjesecu

### Korištene tablice:

| Tablica     | Uloga                                          |
| ----------- | ---------------------------------------------- |
| `karta`     | Glavna tablica - podaci o prodanim kartama     |
| `tip_karte` | Tipovi karata (dnevne, mjesečne, godišnje...)  |
| `prekrsaji` | Evidencija prekršaja za korelaciju s prihodima |

### Poslovni benefiti prikazanih informacija:

1. **Praćenje prihoda** - Mjesečni pregled prihoda omogućuje praćenje financijske uspješnosti tvrtke i usporedbu s planiranim budžetom
2. **Sezonska analiza** - Identifikacija mjeseci s većom/manjom prodajom pomaže u planiranju kampanja i promocija
3. **Analiza baze korisnika** - Broj jedinstvenih kupaca pokazuje širinu korisničke baze, dok omjer karte/kupac pokazuje lojalnost
4. **Preferencije korisnika** - Najpopularniji tip karte ukazuje na potrebe putnika i pomaže u definiranju ponude
5. **Korelacija s prekršajima** - Usporedba prihoda i prekršaja može pokazati utjecaj pojačanih kontrola na prodaju karata
6. **Prosječna cijena** - Praćenje prosječne cijene pomaže u evaluaciji cjenovne politike i popusta
7. **Planiranje kapaciteta** - Mjeseci s više prodanih karata zahtijevaju više vozila i osoblja

---

## UPIT 18: Kompleksna analiza voznog reda s rangiranjem

### SQL kod:

```sql
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
```

### Opis SQL operacija:

- **Višestruki INNER JOIN-ovi** - spaja 5 tablica:
  - `vozni_red vr` - glavna tablica
  - `linije l` - podaci o liniji
  - `vozila v` - podaci o vozilu
  - `zaposlenik z` - podaci o vozaču
  - `kalendari kal` - tip dana (radni, vikend, blagdan)
- **CONCAT(z.ime, ' ', z.prezime)** - spaja ime i prezime vozača
- **Tri korelirana podupita**:
  - `COUNT(*)` - broji stanice na liniji
  - Prvi `SELECT s.naziv ... ORDER BY ls.redoslijed ASC LIMIT 1` - dohvaća polaznu stanicu
  - Drugi `SELECT s.naziv ... ORDER BY ls.redoslijed DESC LIMIT 1` - dohvaća završnu stanicu
  - `SELECT MAX(ov.datum_servisa)` - dohvaća datum zadnjeg servisa vozila
- **CASE WHEN ... THEN ... ELSE ... END** - kategorizira vrijeme polaska:
  - 05:00 - 09:00 → Jutarnja špica
  - 09:00 - 15:00 → Sredina dana
  - 15:00 - 19:00 → Popodnevna špica
  - Ostalo → Večernja/noćna
- **TIME() funkcija** - ekstrahira samo vrijeme iz datetime polja
- **ORDER BY l.oznaka, vr.vrijeme_polaska** - sortira po liniji i vremenu polaska

### Korištene tablice:

| Tablica             | Uloga                                                |
| ------------------- | ---------------------------------------------------- |
| `vozni_red`         | Glavna tablica - raspored polazaka                   |
| `linije`            | Informacije o linijama (oznaka, naziv, tip, duljina) |
| `vozila`            | Podaci o vozilima (registracija, tip, kapacitet)     |
| `zaposlenik`        | Podaci o vozačima                                    |
| `kalendari`         | Tipovi dana za vozni red                             |
| `linije_stanice`    | Za dohvaćanje broja i naziva stanica                 |
| `stanice`           | Nazivi polazne i završne stanice                     |
| `odrzavanje_vozila` | Datum zadnjeg servisa                                |

### Poslovni benefiti prikazanih informacija:

1. **Potpuni pregled operacija** - Jednim upitom dobivamo sve ključne informacije o voznom redu potrebne za upravljanje prometom
2. **Upravljanje vozačima** - Pregled koji vozač vozi koju liniju omogućuje praćenje radnog opterećenja i planiranje smjena
3. **Kategorizacija po smjenama** - Podjela na jutarnju špicu, sredinu dana, popodnevnu špicu i noćni promet pomaže u analizi frekvencije vožnji
4. **Praćenje održavanja** - Datum zadnjeg servisa vozila pomaže u prevenciji kvarova i planiranju održavanja
5. **Kapacitet vozila** - Informacija o kapacitetu putnika pomaže u optimizaciji rasporeda vozila na prometnije linije
6. **Vizualizacija ruta** - Polazna i završna stanica daju brzi uvid u trasu linije bez pregleda svih stanica
7. **Operativna analiza** - Podaci o duljini trase, broju stanica i tipu vozila omogućuju izračun prosječnog vremena vožnje
8. **Planiranje kapaciteta** - Kombinacija podataka o vremenu (špica vs. ostalo) i kapacitetu vozila omogućuje optimalnu raspodjelu resursa

---

## Sažetak korištenih SQL tehnika

| Tehnika                                 | Upit 16 | Upit 17 | Upit 18 |
| --------------------------------------- | :-----: | :-----: | :-----: |
| INNER JOIN                              |    ✓    |    ✓    |    ✓    |
| LEFT JOIN                               |    ✓    |         |         |
| Korelirani podupiti                     |    ✓    |    ✓    |    ✓    |
| Derived tables (FROM podupit)           |         |    ✓    |         |
| GROUP_CONCAT                            |    ✓    |         |         |
| CASE WHEN                               |         |         |    ✓    |
| Agregacijske funkcije (COUNT, SUM, AVG) |    ✓    |    ✓    |    ✓    |
| DATE_FORMAT                             |         |    ✓    |         |
| HAVING                                  |    ✓    |         |         |
| ORDER BY + LIMIT                        |    ✓    |    ✓    |    ✓    |
