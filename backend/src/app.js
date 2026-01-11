import express from "express";
import cors from "cors";
import { apiRouter } from "./routes.api.js";

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: "1mb" }));

  app.use("/api", apiRouter);

  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: "Server error" });
  });

  return app;
}
