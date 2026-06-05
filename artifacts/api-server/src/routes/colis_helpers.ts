import { db, colisTable, garesTable, usersTable } from "@workspace/db";
import { eq } from "drizzle-orm";

export async function formatColis(c: typeof colisTable.$inferSelect) {
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
