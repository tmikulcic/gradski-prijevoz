import "dotenv/config";
import { createApp } from "./app.js";
import { pool } from "./db.js";

const app = createApp();
const PORT = Number(process.env.PORT || 3000);

async function boot() {
  await pool.query("SELECT 1");
  app.listen(PORT, () => {
    console.log(`API running on http://localhost:${PORT}`);
  });
}

boot().catch((e) => {
  console.error("Boot failed:", e);
  process.exit(1);
});
