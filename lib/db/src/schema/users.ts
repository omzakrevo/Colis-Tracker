import { pgTable, serial, text, boolean, integer, timestamp } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const usersTable = pgTable("users", {
  id: serial("id").primaryKey(),
  nom: text("nom").notNull(),
  username: text("username").notNull().unique(),
  password_hash: text("password_hash").notNull(),
  role: text("role").notNull().default("agent"),
  gare_id: integer("gare_id"),
  telephone: text("telephone"),
  actif: boolean("actif").notNull().default(true),
  created_at: timestamp("created_at").notNull().defaultNow(),
});

export const insertUserSchema = createInsertSchema(usersTable).omit({ id: true, created_at: true });
export type InsertUser = z.infer<typeof insertUserSchema>;
export type User = typeof usersTable.$inferSelect;
