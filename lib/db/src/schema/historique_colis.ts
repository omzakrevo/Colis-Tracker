import { pgTable, serial, integer, text, timestamp } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const historiqueColis = pgTable("historique_colis", {
  id: serial("id").primaryKey(),
  colis_id: integer("colis_id").notNull(),
  statut: text("statut").notNull(),
  notes: text("notes"),
  agent_id: integer("agent_id"),
  date_changement: text("date_changement").notNull(),
  created_at: timestamp("created_at").notNull().defaultNow(),
});

export const insertHistoriqueSchema = createInsertSchema(historiqueColis).omit({ id: true, created_at: true });
export type InsertHistorique = z.infer<typeof insertHistoriqueSchema>;
export type HistoriqueColis = typeof historiqueColis.$inferSelect;
