# Digitalization Program Cockpit — MVP

Governance preparation and portfolio steering tool for a Digitalization Program Manager.
Manages the flow: employee idea → triage → qualification (L1) → Business Case / Charter
preparation (L2) → G1 approval → conversion to project (S1), with decision log,
SmartSheet import/export and an exception-based cockpit.

**Stack:** React (Vite) + Supabase (Postgres, Auth, RLS). No custom backend server needed for the MVP.

## 1. Setup

### Supabase
1. Create a project at https://supabase.com (free tier is fine).
2. Open **SQL Editor** → paste and run `supabase/schema.sql`.
3. (Optional) In **Authentication → Providers → Email**, disable "Confirm email" for faster onboarding during pilots.
4. Copy the project URL and anon key from **Settings → API**.

### App
```bash
cp .env.example .env        # fill VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev                 # local
npm run build               # production build (dist/)
```

### First user / roles
Sign up in the app, then promote yourself in the Supabase SQL editor:
```sql
update public.profiles set role = 'program_manager' where email = 'you@company.com';
```
After that, manage roles from **Users & Roles** in the app. Roles: Requester,
Program Manager, Transformation Team, Project Lead — permissions are enforced
server-side by Postgres RLS (see `schema.sql`), not just hidden in the UI.

## 2. Deployment
- **Vercel / Netlify:** import the repo, set the two `VITE_*` env vars, build command `npm run build`, output `dist/`.
- SPA routing: add a rewrite of `/*` → `/index.html`
  (Vercel: `vercel.json` provided; Netlify: `public/_redirects` provided).

## 3. SmartSheet exchange (Phase 1)
- **Import:** SmartSheet I/O screen → upload the SmartSheet XLSX/CSV export.
  Column mapping matches the official structure (`Id`, `Project Name`, `CAPEX k€`, …).
  Duplicates are detected and shown as updates before you confirm. Import timestamp
  and source file are stored per project.
- **Export:** converted initiatives are exported as a SmartSheet-ready XLSX with the
  same column structure. Required fields are validated first.
- The app never writes to SmartSheet implicitly — SmartSheet stays the source of truth.

## 4. Architecture notes (client migration / Databricks)
The target deployment at the client will use their own platform (likely Databricks).
Two decisions keep that migration cheap:

1. **Single data-access layer:** all reads/writes go through `src/lib/api.js`.
   Migrating means reimplementing that one module (e.g. against Databricks
   **Lakebase** — managed Postgres — or a thin API). Screens and business logic
   (`src/lib/logic.js`, pure functions) are backend-agnostic.
2. **Standard Postgres schema:** `supabase/schema.sql` uses vanilla Postgres
   (tables, triggers, functions). It ports to Lakebase nearly as-is.
   What must be re-worked at the client: authentication (Supabase Auth → client SSO,
   e.g. Entra ID) and the RLS policies' identity source (`auth.uid()`).

Future roadmap hooks already in the product: LLM-guided intake (visible roadmap
notes in Ideation/BC/Charter, data model ready), direct SmartSheet connector (Phase 2).

## 5. Structure
```
supabase/schema.sql        # tables, triggers, RPCs (qualify_idea, convert_to_project), RLS
src/lib/api.js             # ONLY module talking to Supabase (migration seam)
src/lib/logic.js           # pure business rules: transition criteria, scoring, alerts
src/lib/smartsheet.js      # XLSX/CSV mapping (SheetJS)
src/lib/constants.js       # reference data: pillars, stages, templates, checklists
src/pages/                 # Cockpit, IdeationBoard, IdeaDetail, editors, DecisionLog,
                           # Projects, ImportExport, Notifications, Admin, Login
```
