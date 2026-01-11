export const TABLES = {
  zone: {
    pk: ["id"],
    columns: ["id", "zona_kod", "zona_naziv", "created_at"],
    searchColumns: ["zona_kod", "zona_naziv"]
  },
  vozila: {
    pk: ["id"],
    columns: ["id", "tip_vozila", "registarska_oznaka", "u_prometu", "vrsta_goriva", "kapacitet_putnika"],
    searchColumns: ["tip_vozila", "registarska_oznaka", "vrsta_goriva"]
  },
  linije: {
    pk: ["id"],
    columns: ["id", "oznaka", "naziv", "tip_linije", "duljina_km"],
    searchColumns: ["oznaka", "naziv", "tip_linije"]
  },
  stanice: {
    pk: ["id"],
    columns: ["id", "naziv", "zona_id"],
    searchColumns: ["naziv"]
  },
  zaposlenik: {
    pk: ["id"],
    columns: ["id", "zaposlenik_broj", "ime", "prezime", "oib", "email", "naziv_uloge", "datum_zaposlenja"],
    searchColumns: ["zaposlenik_broj", "ime", "prezime", "email", "naziv_uloge", "oib"]
  },
  kalendari: {
    pk: ["id"],
    columns: ["id", "kalendar_naziv", "ponedjeljak", "utorak", "srijeda", "cetvrtak", "petak", "subota", "nedjelja"],
    searchColumns: ["kalendar_naziv"]
  },
  vozni_red: {
    pk: ["id"],
    columns: ["id", "linija_id", "vozilo_id", "vozac_id", "kalendar_id", "vrijeme_polaska"],
    searchColumns: ["vrijeme_polaska"]
  },
  kategorija_putnik: {
    pk: ["id"],
    columns: ["id", "kategorija_naziv", "kategorija_kod", "min_dob", "max_dob", "postotak_popusta"],
    searchColumns: ["kategorija_naziv", "kategorija_kod"]
  },
  korisnici: {
    pk: ["id"],
    columns: ["id", "kategorija_id", "ime", "prezime", "email", "datum_rodenja", "status_racuna"],
    searchColumns: ["ime", "prezime", "email", "status_racuna"]
  },
  tip_karte: {
    pk: ["id"],
    columns: ["id", "tip_naziv", "tip_kod", "osnovna_cijena", "trajanje_minute"],
    searchColumns: ["tip_naziv", "tip_kod"]
  },
  karta: {
    pk: ["id"],
    columns: ["id", "tip_karte_id", "korisnik_id", "karta_kod", "datum_kupnje", "vrijedi_do", "placena_cijena"],
    searchColumns: ["karta_kod"]
  },
  prekrsaji: {
    pk: ["id"],
    columns: ["id", "korisnik_id", "zaposlenik_id", "datum_prekrsaja", "iznos_kazne", "status_placanja", "napomena"],
    searchColumns: ["status_placanja"]
  },
  odrzavanje_vozila: {
    pk: ["id"],
    columns: ["id", "vozilo_id", "zaposlenik_id", "datum_servisa", "vrsta_servisa", "trosak_servisa", "opis_radova"],
    searchColumns: ["vrsta_servisa"]
  },
  prituzbe: {
    pk: ["id"],
    columns: ["id", "korisnik_id", "linija_id", "datum_prituzbe", "kategorija_prituzbe", "tekst_prituzbe", "status_rjesavanja"],
    searchColumns: ["kategorija_prituzbe", "status_rjesavanja"]
  }
};

export const LINije_STANICE = {
  table: "linije_stanice",
  pk: ["linija_id", "stanica_id"],
  columns: ["linija_id", "stanica_id", "redoslijed"],
  searchColumns: []
};
