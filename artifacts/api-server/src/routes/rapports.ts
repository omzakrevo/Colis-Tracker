import { Router } from "express";
import { db, colisTable, garesTable, usersTable } from "@workspace/db";
import { eq, and, gte, lte, sql, count, sum, ne } from "drizzle-orm";
import { logger } from "../lib/logger";

const router = Router();

router.get("/rapports/dashboard", async (req, res) => {
  try {
    const today = new Date().toISOString().slice(0, 10);

    const [{ total_colis }] = await db.select({ total_colis: count() }).from(colisTable);
    const [{ colis_aujourd_hui }] = await db.select({ colis_aujourd_hui: count() }).from(colisTable).where(eq(colisTable.date_envoi, today));
    const [{ colis_en_route }] = await db.select({ colis_en_route: count() }).from(colisTable).where(eq(colisTable.statut, "en_route"));
    const [{ colis_arrives }] = await db.select({ colis_arrives: count() }).from(colisTable).where(eq(colisTable.statut, "arrive"));
    const [{ colis_non_retires }] = await db.select({ colis_non_retires: count() }).from(colisTable).where(eq(colisTable.statut, "arrive"));
    const [{ recette_totale }] = await db.select({ recette_totale: sum(colisTable.prix) }).from(colisTable).where(ne(colisTable.statut, "annule"));
    const [{ recette_aujourd_hui }] = await db.select({ recette_aujourd_hui: sum(colisTable.prix) }).from(colisTable).where(and(eq(colisTable.date_envoi, today), ne(colisTable.statut, "annule")));
    const [{ total_gares }] = await db.select({ total_gares: count() }).from(garesTable);
    const [{ total_agents }] = await db.select({ total_agents: count() }).from(usersTable).where(eq(usersTable.actif, true));

    return res.json({
      total_colis: Number(total_colis),
      colis_aujourd_hui: Number(colis_aujourd_hui),
      colis_en_route: Number(colis_en_route),
      colis_arrives: Number(colis_arrives),
      colis_non_retires: Number(colis_non_retires),
      recette_totale: parseFloat(recette_totale ?? "0"),
      recette_aujourd_hui: parseFloat(recette_aujourd_hui ?? "0"),
      total_gares: Number(total_gares),
      total_agents: Number(total_agents),
    });
  } catch (err) {
    logger.error({ err }, "Dashboard stats error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/rapports/colis-par-jour", async (req, res) => {
  try {
    const { date_debut, date_fin } = req.query as { date_debut?: string; date_fin?: string };
    const conditions = [];
    if (date_debut) conditions.push(gte(colisTable.date_envoi, date_debut));
    if (date_fin) conditions.push(lte(colisTable.date_envoi, date_fin));

    const query = conditions.length > 0
      ? db.select({
          date: colisTable.date_envoi,
          total: count(),
          recette: sum(colisTable.prix),
        }).from(colisTable).where(and(...conditions)).groupBy(colisTable.date_envoi).orderBy(colisTable.date_envoi)
      : db.select({
          date: colisTable.date_envoi,
          total: count(),
          recette: sum(colisTable.prix),
        }).from(colisTable).groupBy(colisTable.date_envoi).orderBy(colisTable.date_envoi);

    const rows = await query;
    return res.json(rows.map(r => ({
      date: r.date,
      total: Number(r.total),
      recette: parseFloat(r.recette ?? "0"),
    })));
  } catch (err) {
    logger.error({ err }, "Colis par jour error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/rapports/recettes-par-gare", async (req, res) => {
  try {
    const rows = await db.select({
      gare_id: garesTable.id,
      gare_nom: garesTable.nom,
      total_colis: count(colisTable.id),
      recette_totale: sum(colisTable.prix),
    })
      .from(garesTable)
      .leftJoin(colisTable, eq(colisTable.gare_depart_id, garesTable.id))
      .groupBy(garesTable.id, garesTable.nom)
      .orderBy(garesTable.nom);

    return res.json(rows.map(r => ({
      gare_id: r.gare_id,
      gare_nom: r.gare_nom,
      total_colis: Number(r.total_colis),
      recette_totale: parseFloat(r.recette_totale ?? "0"),
    })));
  } catch (err) {
    logger.error({ err }, "Recettes par gare error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/rapports/recettes-par-agent", async (req, res) => {
  try {
    const rows = await db.select({
      agent_id: usersTable.id,
      agent_nom: usersTable.nom,
      total_colis: count(colisTable.id),
      recette_totale: sum(colisTable.prix),
    })
      .from(usersTable)
      .leftJoin(colisTable, eq(colisTable.agent_id, usersTable.id))
      .where(eq(usersTable.role, "agent"))
      .groupBy(usersTable.id, usersTable.nom)
      .orderBy(usersTable.nom);

    return res.json(rows.map(r => ({
      agent_id: r.agent_id,
      agent_nom: r.agent_nom,
      total_colis: Number(r.total_colis),
      recette_totale: parseFloat(r.recette_totale ?? "0"),
    })));
  } catch (err) {
    logger.error({ err }, "Recettes par agent error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/rapports/colis-non-retires", async (req, res) => {
  try {
    const list = await db.select().from(colisTable).where(eq(colisTable.statut, "arrive")).orderBy(sql`${colisTable.created_at} ASC`);
    const formatted = await Promise.all(list.map(async (c) => {
      const [gareDepart] = await db.select({ nom: garesTable.nom }).from(garesTable).where(eq(garesTable.id, c.gare_depart_id)).limit(1);
      const [gareArrivee] = await db.select({ nom: garesTable.nom }).from(garesTable).where(eq(garesTable.id, c.gare_arrivee_id)).limit(1);
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
        agent_nom: null,
        retrait_nom: c.retrait_nom ?? null,
        retrait_telephone: c.retrait_telephone ?? null,
        retrait_piece_identite: c.retrait_piece_identite ?? null,
        retrait_date: c.retrait_date ?? null,
        notes: c.notes ?? null,
        created_at: c.created_at.toISOString(),
      };
    }));
    return res.json(formatted);
  } catch (err) {
    logger.error({ err }, "Colis non retirés error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/rapports/statuts-summary", async (req, res) => {
  try {
    const rows = await db.select({
      statut: colisTable.statut,
      total: count(),
    }).from(colisTable).groupBy(colisTable.statut);

    return res.json(rows.map(r => ({
      statut: r.statut,
      total: Number(r.total),
    })));
  } catch (err) {
    logger.error({ err }, "Statuts summary error");
    return res.status(500).json({ error: "Server error" });
  }
});

export default router;
