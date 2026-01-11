# Gradski prijevoz – Node.js + Express + MySQL + plain HTML/JS/CSS

## 1) Backend
```bash
cd backend
npm i
cp .env.example .env
# u .env upiši remote DB podatke
npm run dev
```

API: `http://localhost:3000/api`

### Endpointi
- `GET /api/health`
- `GET /api/tables`
- CRUD (sve tablice iz whitelist-a):
  - `GET /api/crud/:table?page=1&pageSize=25&search=...`
  - `GET /api/crud/:table/:id`
  - `POST /api/crud/:table`
  - `PUT /api/crud/:table/:id`
  - `DELETE /api/crud/:table/:id`
- Posebno (kompozitni ključ):
  - `GET /api/linije-stanice`
  - `POST /api/linije-stanice`
  - `PUT /api/linije-stanice`
  - `DELETE /api/linije-stanice`

## 2) Frontend
Otvori `frontend/index.html` u browseru (ili Live Server).

Frontend očekuje da backend radi na `http://localhost:3000`.

## Napomena
Credentialse nemoj commitati u repo. Drži ih samo u `.env` (koji se ne commita).
