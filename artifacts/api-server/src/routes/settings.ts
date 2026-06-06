import { Router } from "express";
import { db } from "@workspace/db";
import { companySettings } from "@workspace/db/schema";
import { eq } from "drizzle-orm";

const router = Router();

async function getOrCreate() {
  const rows = await db.select().from(companySettings).limit(1);
  if (rows.length > 0) return rows[0];
  const [created] = await db.insert(companySettings).values({}).returning();
  return created;
}

router.get("/settings/company", async (req, res) => {
  try {
    const settings = await getOrCreate();
    res.json(settings);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Erreur serveur" });
  }
});

router.put("/settings/company", async (req, res) => {
  const user = (req.session as any);
  if (!user?.userId || user?.role !== "admin") {
    return res.status(403).json({ error: "Accès refusé" });
  }
  try {
    const settings = await getOrCreate();
    const { nom, slogan, telephone, email, adresse, ville, pays, logo } = req.body as {
      nom?: string; slogan?: string; telephone?: string; email?: string;
      adresse?: string; ville?: string; pays?: string; logo?: string | null;
    };
    const [updated] = await db.update(companySettings)
      .set({
        ...(nom       !== undefined && { nom }),
        ...(slogan    !== undefined && { slogan }),
        ...(telephone !== undefined && { telephone }),
        ...(email     !== undefined && { email }),
        ...(adresse   !== undefined && { adresse }),
        ...(ville     !== undefined && { ville }),
        ...(pays      !== undefined && { pays }),
        ...(logo      !== undefined && { logo: logo ?? null }),
      })
      .where(eq(companySettings.id, settings.id))
      .returning();
    res.json(updated);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Erreur serveur" });
  }
});

export default router;
