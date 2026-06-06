import { pgTable, serial, text, integer, numeric, timestamp } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const colisTable = pgTable("colis", {
  id: serial("id").primaryKey(),
  numero: text("numero").notNull().unique(),
  expediteur_nom: text("expediteur_nom").notNull(),
  expediteur_telephone: text("expediteur_telephone").notNull(),
  destinataire_nom: text("destinataire_nom").notNull(),
  destinataire_telephone: text("destinataire_telephone").notNull(),
  gare_depart_id: integer("gare_depart_id").notNull(),
  gare_arrivee_id: integer("gare_arrivee_id").notNull(),
  description: text("description").notNull(),
  nombre: integer("nombre").notNull().default(1),
  poids: numeric("poids", { precision: 10, scale: 2 }),
  prix: numeric("prix", { precision: 10, scale: 2 }).notNull(),
  statut: text("statut").notNull().default("enregistre"),
  date_envoi: text("date_envoi").notNull(),
  agent_id: integer("agent_id"),
  retrait_nom: text("retrait_nom"),
  retrait_telephone: text("retrait_telephone"),
  retrait_piece_identite: text("retrait_piece_identite"),
  retrait_signature: text("retrait_signature"),
  retrait_date: text("retrait_date"),
  notes: text("notes"),
  created_at: timestamp("created_at").notNull().defaultNow(),
});

export const insertColisSchema = createInsertSchema(colisTable).omit({ id: true, numero: true, created_at: true });
export type InsertColis = z.infer<typeof insertColisSchema>;
export type Colis = typeof colisTable.$inferSelect;
