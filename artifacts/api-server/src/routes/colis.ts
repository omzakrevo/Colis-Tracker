import { Router } from "express";
import { db, colisTable, garesTable, usersTable, historiqueColis } from "@workspace/db";
import { eq, and, gte, lte, or, ilike, sql } from "drizzle-orm";
import { logger } from "../lib/logger";

const router = Router();

function generateNumero(): string {
  const year = new Date().getFullYear();
  const random = Math.floor(100000 + Math.random() * 900000);
  return `COL-${year}-${random}`;
}

async function formatColis(c: typeof colisTable.$inferSelect) {
  const [gareDepart] = await db.select({ nom: garesTable.nom }).from(garesTable).where(eq(garesTable.id, c.gare_depart_id)).limit(1);
  const [gareArrivee] = await db.select({ nom: garesTable.nom }).from(garesTable).where(eq(garesTable.id, c.gare_arrivee_id)).limit(1);
  let agent_nom: string | null = null;
  if (c.agent_id) {
    const [agent] = await db.select({ nom: usersTable.nom }).from(usersTable).where(eq(usersTable.id, c.agent_id)).limit(1);
    agent_nom = agent?.nom ?? null;
  }
  return {
    id: c.id,
    numero: c.numero,
    expediteur_nom: c.expediteur_nom,
    expediteur_telephone: c.expediteur_telephone,
    destinataire_nom: c.destinataire_nom,
    destinataire_telephone: c.destinataire_telephone,
    gare_depart_id: c.gare_depart_id,
    gare_depart_nom: gareDepart?.nom ?? null,
    gare_arrivee_id: c.gare_arrivee_id,
    gare_arrivee_nom: gareArrivee?.nom ?? null,
    description: c.description,
    nombre: c.nombre,
    poids: c.poids ? parseFloat(c.poids) : null,
    prix: parseFloat(c.prix),
    statut: c.statut,
    date_envoi: c.date_envoi,
    agent_id: c.agent_id ?? null,
    agent_nom,
    retrait_nom: c.retrait_nom ?? null,
    retrait_telephone: c.retrait_telephone ?? null,
    retrait_piece_identite: c.retrait_piece_identite ?? null,
    retrait_date: c.retrait_date ?? null,
    notes: c.notes ?? null,
    created_at: c.created_at.toISOString(),
  };
}

router.get("/colis", async (req, res) => {
  try {
    const { statut, gare_depart_id, gare_arrivee_id, date_debut, date_fin, search } = req.query as Record<string, string>;
    const conditions = [];
    if (statut) conditions.push(eq(colisTable.statut, statut));
    if (gare_depart_id) conditions.push(eq(colisTable.gare_depart_id, parseInt(gare_depart_id)));
    if (gare_arrivee_id) conditions.push(eq(colisTable.gare_arrivee_id, parseInt(gare_arrivee_id)));
    if (date_debut) conditions.push(gte(colisTable.date_envoi, date_debut));
    if (date_fin) conditions.push(lte(colisTable.date_envoi, date_fin));
    if (search) {
      conditions.push(
        or(
          ilike(colisTable.numero, `%${search}%`),
          ilike(colisTable.expediteur_nom, `%${search}%`),
          ilike(colisTable.destinataire_nom, `%${search}%`),
          ilike(colisTable.expediteur_telephone, `%${search}%`),
          ilike(colisTable.destinataire_telephone, `%${search}%`)
        )
      );
    }

    const query = conditions.length > 0
      ? db.select().from(colisTable).where(and(...conditions)).orderBy(sql`${colisTable.created_at} DESC`)
      : db.select().from(colisTable).orderBy(sql`${colisTable.created_at} DESC`);

    const list = await query;
    const formatted = await Promise.all(list.map(formatColis));
    return res.json(formatted);
  } catch (err) {
    logger.error({ err }, "List colis error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.post("/colis", async (req, res) => {
  try {
    const body = req.body as {
      expediteur_nom: string; expediteur_telephone: string;
      destinataire_nom: string; destinataire_telephone: string;
      gare_depart_id: number; gare_arrivee_id: number;
      description: string; nombre: number; poids?: number | null;
      prix: number; date_envoi: string; notes?: string | null;
    };

    const userId = (req.session as any)?.userId;
    const numero = generateNumero();

    const [colis] = await db.insert(colisTable).values({
      numero,
      expediteur_nom: body.expediteur_nom,
      expediteur_telephone: body.expediteur_telephone,
      destinataire_nom: body.destinataire_nom,
      destinataire_telephone: body.destinataire_telephone,
      gare_depart_id: body.gare_depart_id,
      gare_arrivee_id: body.gare_arrivee_id,
      description: body.description,
      nombre: body.nombre,
      poids: body.poids != null ? String(body.poids) : null,
      prix: String(body.prix),
      statut: "enregistre",
      date_envoi: body.date_envoi,
      agent_id: userId ?? null,
      notes: body.notes ?? null,
    }).returning();

    await db.insert(historiqueColis).values({
      colis_id: colis.id,
      statut: "enregistre",
      notes: "Colis enregistré",
      agent_id: userId ?? null,
      date_changement: new Date().toISOString(),
    });

    return res.status(201).json(await formatColis(colis));
  } catch (err) {
    logger.error({ err }, "Create colis error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/colis/numero/:numero", async (req, res) => {
  try {
    const [colis] = await db.select().from(colisTable).where(eq(colisTable.numero, req.params.numero)).limit(1);
    if (!colis) return res.status(404).json({ error: "Colis non trouvé" });
    return res.json(await formatColis(colis));
  } catch (err) {
    logger.error({ err }, "Get colis by numero error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/colis/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const [colis] = await db.select().from(colisTable).where(eq(colisTable.id, id)).limit(1);
    if (!colis) return res.status(404).json({ error: "Colis non trouvé" });
    return res.json(await formatColis(colis));
  } catch (err) {
    logger.error({ err }, "Get colis error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.patch("/colis/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const body = req.body as {
      expediteur_nom?: string; expediteur_telephone?: string;
      destinataire_nom?: string; destinataire_telephone?: string;
      description?: string; nombre?: number; poids?: number | null;
      prix?: number; notes?: string | null;
    };
    const updates: Record<string, any> = {};
    if (body.expediteur_nom !== undefined) updates.expediteur_nom = body.expediteur_nom;
    if (body.expediteur_telephone !== undefined) updates.expediteur_telephone = body.expediteur_telephone;
    if (body.destinataire_nom !== undefined) updates.destinataire_nom = body.destinataire_nom;
    if (body.destinataire_telephone !== undefined) updates.destinataire_telephone = body.destinataire_telephone;
    if (body.description !== undefined) updates.description = body.description;
    if (body.nombre !== undefined) updates.nombre = body.nombre;
    if (body.poids !== undefined) updates.poids = body.poids != null ? String(body.poids) : null;
    if (body.prix !== undefined) updates.prix = String(body.prix);
    if (body.notes !== undefined) updates.notes = body.notes;

    const [colis] = await db.update(colisTable).set(updates).where(eq(colisTable.id, id)).returning();
    if (!colis) return res.status(404).json({ error: "Colis non trouvé" });
    return res.json(await formatColis(colis));
  } catch (err) {
    logger.error({ err }, "Update colis error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.patch("/colis/:id/statut", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { statut, notes } = req.body as { statut: string; notes?: string | null };
    const userId = (req.session as any)?.userId;

    const [colis] = await db.update(colisTable).set({ statut }).where(eq(colisTable.id, id)).returning();
    if (!colis) return res.status(404).json({ error: "Colis non trouvé" });

    await db.insert(historiqueColis).values({
      colis_id: id,
      statut,
      notes: notes ?? null,
      agent_id: userId ?? null,
      date_changement: new Date().toISOString(),
    });

    return res.json(await formatColis(colis));
  } catch (err) {
    logger.error({ err }, "Update statut colis error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.post("/colis/:id/retrait", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { retrait_nom, retrait_telephone, retrait_piece_identite } = req.body as {
      retrait_nom: string; retrait_telephone: string; retrait_piece_identite?: string | null;
    };
    const userId = (req.session as any)?.userId;
    const now = new Date().toISOString();

    const [colis] = await db.update(colisTable).set({
      statut: "retire",
      retrait_nom,
      retrait_telephone,
      retrait_piece_identite: retrait_piece_identite ?? null,
      retrait_date: now,
    }).where(eq(colisTable.id, id)).returning();

    if (!colis) return res.status(404).json({ error: "Colis non trouvé" });

    await db.insert(historiqueColis).values({
      colis_id: id,
      statut: "retire",
      notes: `Retiré par ${retrait_nom}`,
      agent_id: userId ?? null,
      date_changement: now,
    });

    return res.json(await formatColis(colis));
  } catch (err) {
    logger.error({ err }, "Retrait colis error");
    return res.status(500).json({ error: "Server error" });
  }
});

export default router;
