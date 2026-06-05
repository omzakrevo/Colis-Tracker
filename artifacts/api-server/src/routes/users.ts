import { Router } from "express";
import { db, usersTable, garesTable } from "@workspace/db";
import { eq } from "drizzle-orm";
import { logger } from "../lib/logger";
import { hashPassword } from "./auth";

const router = Router();

async function formatUser(user: typeof usersTable.$inferSelect) {
  let gare_nom: string | null = null;
  if (user.gare_id) {
    const [gare] = await db.select({ nom: garesTable.nom }).from(garesTable).where(eq(garesTable.id, user.gare_id)).limit(1);
    gare_nom = gare?.nom ?? null;
  }
  return {
    id: user.id,
    nom: user.nom,
    username: user.username,
    role: user.role,
    gare_id: user.gare_id ?? null,
    gare_nom,
    telephone: user.telephone ?? null,
    actif: user.actif,
    created_at: user.created_at.toISOString(),
  };
}

router.get("/users", async (req, res) => {
  try {
    const users = await db.select().from(usersTable).orderBy(usersTable.nom);
    const formatted = await Promise.all(users.map(formatUser));
    return res.json(formatted);
  } catch (err) {
    logger.error({ err }, "List users error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.post("/users", async (req, res) => {
  try {
    const { nom, username, password, role, gare_id, telephone } = req.body as {
      nom: string; username: string; password: string; role: string; gare_id?: number | null; telephone?: string | null;
    };
    if (!nom || !username || !password || !role) {
      return res.status(400).json({ error: "nom, username, password, role requis" });
    }
    const password_hash = hashPassword(password);
    const [user] = await db.insert(usersTable).values({
      nom, username, password_hash, role, gare_id: gare_id ?? null, telephone: telephone ?? null,
    }).returning();
    return res.status(201).json(await formatUser(user));
  } catch (err) {
    logger.error({ err }, "Create user error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.get("/users/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const [user] = await db.select().from(usersTable).where(eq(usersTable.id, id)).limit(1);
    if (!user) return res.status(404).json({ error: "Utilisateur non trouvé" });
    return res.json(await formatUser(user));
  } catch (err) {
    logger.error({ err }, "Get user error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.patch("/users/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { nom, username, password, role, gare_id, telephone, actif } = req.body as {
      nom?: string; username?: string; password?: string; role?: string;
      gare_id?: number | null; telephone?: string | null; actif?: boolean;
    };
    const updates: Record<string, any> = {};
    if (nom !== undefined) updates.nom = nom;
    if (username !== undefined) updates.username = username;
    if (password !== undefined) updates.password_hash = hashPassword(password);
    if (role !== undefined) updates.role = role;
    if (gare_id !== undefined) updates.gare_id = gare_id;
    if (telephone !== undefined) updates.telephone = telephone;
    if (actif !== undefined) updates.actif = actif;

    const [user] = await db.update(usersTable).set(updates).where(eq(usersTable.id, id)).returning();
    if (!user) return res.status(404).json({ error: "Utilisateur non trouvé" });
    return res.json(await formatUser(user));
  } catch (err) {
    logger.error({ err }, "Update user error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.delete("/users/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    await db.delete(usersTable).where(eq(usersTable.id, id));
    return res.status(204).end();
  } catch (err) {
    logger.error({ err }, "Delete user error");
    return res.status(500).json({ error: "Server error" });
  }
});

export default router;
