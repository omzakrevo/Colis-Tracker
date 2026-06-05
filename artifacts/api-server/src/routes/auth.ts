import { Router } from "express";
import { db, usersTable, garesTable } from "@workspace/db";
import { eq } from "drizzle-orm";
import { logger } from "../lib/logger";

const router = Router();

function hashPassword(password: string): string {
  const crypto = require("crypto");
  return crypto.createHash("sha256").update(password + "vip_colis_salt").digest("hex");
}

function verifyPassword(password: string, hash: string): boolean {
  return hashPassword(password) === hash;
}

router.post("/auth/login", async (req, res) => {
  try {
    const { username, password } = req.body as { username: string; password: string };
    if (!username || !password) {
      return res.status(400).json({ error: "Username and password required" });
    }

    const [user] = await db.select().from(usersTable).where(eq(usersTable.username, username)).limit(1);
    if (!user || !verifyPassword(password, user.password_hash)) {
      return res.status(401).json({ error: "Identifiants incorrects" });
    }

    if (!user.actif) {
      return res.status(401).json({ error: "Compte désactivé" });
    }

    let gare_nom: string | null = null;
    if (user.gare_id) {
      const [gare] = await db.select({ nom: garesTable.nom }).from(garesTable).where(eq(garesTable.id, user.gare_id)).limit(1);
      gare_nom = gare?.nom ?? null;
    }

    (req.session as any).userId = user.id;

    return res.json({
      user: {
        id: user.id,
        nom: user.nom,
        username: user.username,
        role: user.role,
        gare_id: user.gare_id ?? null,
        gare_nom,
        telephone: user.telephone ?? null,
        actif: user.actif,
        created_at: user.created_at.toISOString(),
      },
    });
  } catch (err) {
    logger.error({ err }, "Login error");
    return res.status(500).json({ error: "Server error" });
  }
});

router.post("/auth/logout", (req, res) => {
  (req.session as any).destroy?.(() => {});
  return res.json({ ok: true });
});

router.get("/auth/me", async (req, res) => {
  try {
    const userId = (req.session as any)?.userId;
    if (!userId) {
      return res.status(401).json({ error: "Not authenticated" });
    }

    const [user] = await db.select().from(usersTable).where(eq(usersTable.id, userId)).limit(1);
    if (!user) {
      return res.status(401).json({ error: "User not found" });
    }

    let gare_nom: string | null = null;
    if (user.gare_id) {
      const [gare] = await db.select({ nom: garesTable.nom }).from(garesTable).where(eq(garesTable.id, user.gare_id)).limit(1);
      gare_nom = gare?.nom ?? null;
    }

    return res.json({
      id: user.id,
      nom: user.nom,
      username: user.username,
      role: user.role,
      gare_id: user.gare_id ?? null,
      gare_nom,
      telephone: user.telephone ?? null,
      actif: user.actif,
      created_at: user.created_at.toISOString(),
    });
  } catch (err) {
    logger.error({ err }, "GetMe error");
    return res.status(500).json({ error: "Server error" });
  }
});

export { hashPassword };
export default router;
