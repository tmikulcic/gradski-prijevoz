import mysql from "mysql2/promise";

const sslEnabled = String(process.env.DB_SSL || "").toLowerCase() === "true";

export const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,

  // ključna stvar: da DATE/DATETIME ne dođu kao JS Date -> ISO string
  dateStrings: true,

  ssl: sslEnabled ? { rejectUnauthorized: false } : undefined
});