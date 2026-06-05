# VIP Colis

Application web de gestion de colis pour compagnie de transport. Permet d'enregistrer, suivre et gérer des colis entre agences/gares, avec génération de reçus et rapports.

## Run & Operate

- `pnpm --filter @workspace/api-server run dev` — run the API server (port 8080)
- `pnpm --filter @workspace/vip-colis run dev` — run the frontend (port 22534)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required env: `DATABASE_URL` — Postgres connection string, `SESSION_SECRET` — session key

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- API: Express 5 + express-session (cookie-based sessions)
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- Frontend: React + Vite + Wouter + TanStack Query + shadcn/ui
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

- `lib/api-spec/openapi.yaml` — OpenAPI spec (source of truth for all contracts)
- `lib/db/src/schema/` — Drizzle schema: users.ts, gares.ts, colis.ts, historique_colis.ts
- `artifacts/api-server/src/routes/` — Express routes: auth, users, gares, colis, historique, rapports
- `artifacts/vip-colis/src/pages/` — Frontend pages: login, dashboard, colis/, gares/, utilisateurs/, rapports, recherche
- `lib/api-client-react/src/generated/` — Generated React Query hooks (DO NOT EDIT)
- `lib/api-zod/src/generated/` — Generated Zod schemas (DO NOT EDIT)

## Architecture decisions

- Session-based authentication (express-session + SHA-256 password hashing)
- Custom fetch with `credentials: "include"` so cookies are sent cross-origin
- OpenAPI-first: all contracts defined in openapi.yaml, then codegen generates hooks and Zod schemas
- Package tracking numbers auto-generated as `COL-YYYY-XXXXXX`
- Status history tracked in `historique_colis` table on every status change

## Product

- Enregistrement de colis avec numéro de suivi automatique (COL-YYYY-XXXXXX)
- Suivi du statut: enregistré → chargé → en route → arrivé → retiré / annulé
- Gestion des gares (agences) et des utilisateurs (admin, chef de gare, agent)
- Génération de reçus imprimables
- Recherche rapide par numéro, nom, téléphone, gare
- Rapports: colis par jour, recettes par gare/agent, statuts

## User preferences

_Populate as you build — explicit user instructions worth remembering across sessions._

## Comptes de démonstration

| Rôle | Username | Mot de passe |
|------|----------|--------------|
| Administrateur | `admin` | `admin123` |
| Chef de gare (Ouagadougou) | `chef_oua` | `chef123` |
| Agent (Bobo-Dioulasso) | `agent_bobo` | `agent123` |
| Agent (Banfora) | `agent_ban` | `agent123` |

## Gotchas

- Always run `pnpm --filter @workspace/api-spec run codegen` after any OpenAPI spec change
- Run `pnpm run typecheck:libs` after any lib change before checking artifacts
- The `credentials: "include"` in `lib/api-client-react/src/custom-fetch.ts` is required for session cookie propagation

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
