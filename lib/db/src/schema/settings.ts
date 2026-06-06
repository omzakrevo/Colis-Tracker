import { pgTable, serial, text } from "drizzle-orm/pg-core";

export const companySettings = pgTable("company_settings", {
  id: serial("id").primaryKey(),
  nom: text("nom").notNull().default("VIP Colis"),
  slogan: text("slogan").notNull().default("Réseau de transport express — Burkina Faso"),
  telephone: text("telephone").notNull().default(""),
  email: text("email").notNull().default(""),
  adresse: text("adresse").notNull().default(""),
  ville: text("ville").notNull().default(""),
  pays: text("pays").notNull().default("Burkina Faso"),
  logo: text("logo"),
});
