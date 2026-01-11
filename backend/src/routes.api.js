import express from "express";
import { crudRouter } from "./routes.crud.js";
import { linijeStaniceRouter } from "./routes.linijeStanice.js";
import { TABLES } from "./config.tables.js";

export const apiRouter = express.Router();

apiRouter.get("/health", (req, res) => res.json({ ok: true }));

apiRouter.get("/tables", (req, res) => {
  res.json({
    tables: Object.keys(TABLES),
    special: ["linije_stanice"]
  });
});

apiRouter.use("/crud", crudRouter);
apiRouter.use("/linije-stanice", linijeStaniceRouter);
