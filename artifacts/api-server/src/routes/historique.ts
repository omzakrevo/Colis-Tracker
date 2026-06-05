import { Router } from "express";
import { db, historiqueColis, usersTable } from "@workspace/db";
import { eq } from "drizzle-orm";
import { logger } from "../lib/logger";
import { sql } from "drizzle-orm";

const router = Router();

router.get("/historique/:colis_id", async (req, res) => {
  try {
    const colisId = parseInt(req.params.colis_id);
    const items = await db.select().from(historiqueColis)
      .where(eq(historiqueColis.colis_id, colisId))
      .orderBy(sql`${historiqueColis.created_at} ASC`);

    const formatted = await Promise.all(items.map(async (item) => {
      let agent_nom: string | null = null;
      if (item.agent_id) {
        const [agent] = await db.select({ nom: usersTable.nom }).from(usersTable).where(eq(usersTable.id, item.agent_id)).limit(1);
        agent_nom = agent?.nom ?? null;
      }
      return {
        id: item.id,
        colis_id: item.colis_id,
        statut: item.statut,
        notes: item.notes ?? null,
        agent_id: item.agent_id ?? null,
        agent_nom,
        date_changement: item.date_changement,
        created_at: item.created_at.toISOString(),
      };
    }));

    return res.json(formatted);
  } catch (err) {
    logger.error({ err }, "Get historique error");
    return res.status(500).json({ error: "Server error" });
  }
});

export default router;
