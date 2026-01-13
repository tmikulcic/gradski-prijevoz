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

## 2) Frontend

- Otvori `frontend/index.html` u browseru (ili pomoću Live Servera)  
  → **Admin panel** (CRUD nad tablicama)

- Otvori `frontend/ops.html` u browseru (ili pomoću Live Servera)  
  → **Operativni panel** (dashboard, vozni red, pritužbe, održavanje)

Frontend očekuje da backend radi na `http://localhost:3000`.
