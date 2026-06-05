import { Router } from "express";
import { db, garesTable } from "@workspace/db";
import { eq } from "drizzle-orm";
import { logger } from "../lib/logger";

const router = Router();

router.get("/gares", async (req, res) => {
  try {
    const gares = await db.select().from(garesTable).orderBy(garesTable.nom);
    return res.json(gares.map(g => ({
      ...g,
      created_at: g.created_at.toISOString(),
    })));
  } catch (err) {
    logger.error({ err }, "List gares error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.post("/gares", async (req, res) => {
  try {
    const { nom, ville, adresse, responsable, telephone } = req.body as {
      nom: string; ville: string; adresse: string; responsable?: string; telephone?: string;
    };
    if (!nom || !ville || !adresse) {
      return res.status(400).json({ error: "nom, ville, adresse requis" });
    }
    const [gare] = await db.insert(garesTable).values({ nom, ville, adresse, responsable: responsable ?? null, telephone: telephone ?? null }).returning();
    return res.status(201).json({ ...gare, created_at: gare.created_at.toISOString() });
  } catch (err) {
    logger.error({ err }, "Create gare error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/gares/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const [gare] = await db.select().from(garesTable).where(eq(garesTable.id, id)).limit(1);
    if (!gare) return res.status(404).json({ error: "Gare non trouvée" });
    return res.json({ ...gare, created_at: gare.created_at.toISOString() });
  } catch (err) {
    logger.error({ err }, "Get gare error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.patch("/gares/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const updates = req.body as { nom?: string; ville?: string; adresse?: string; responsable?: string | null; telephone?: string | null };
    const [gare] = await db.update(garesTable).set(updates).where(eq(garesTable.id, id)).returning();
    if (!gare) return res.status(404).json({ error: "Gare non trouvée" });
    return res.json({ ...gare, created_at: gare.created_at.toISOString() });
  } catch (err) {
    logger.error({ err }, "Update gare error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.delete("/gares/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    await db.delete(garesTable).where(eq(garesTable.id, id));
    return res.status(204).end();
  } catch (err) {
    logger.error({ err }, "Delete gare error");
    return res.status(500).json({ error: "Server error" });
  }
});

export default router;
