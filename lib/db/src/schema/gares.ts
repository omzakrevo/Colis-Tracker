import { pgTable, serial, text, timestamp } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const garesTable = pgTable("gares", {
  id: serial("id").primaryKey(),
  nom: text("nom").notNull(),
  ville: text("ville").notNull(),
  adresse: text("adresse").notNull(),
  responsable: text("responsable"),
  telephone: text("telephone"),
  created_at: timestamp("created_at").notNull().defaultNow(),
});

export const insertGareSchema = createInsertSchema(garesTable).omit({ id: true, created_at: true });
export type InsertGare = z.infer<typeof insertGareSchema>;
export type Gare = typeof garesTable.$inferSelect;
