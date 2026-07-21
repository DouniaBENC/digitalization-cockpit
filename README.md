# PWT Digital Pulse

Gouvernance de bout en bout du portefeuille de digitalisation : soumission d'idée → triage → qualification (L1) → Business Case / Project Charter → comité G1 → conversion en projet → suivi SmartSheet → Cockpit exécutif (SteerCo-ready en moins de 30 min).

## Structure du repo

- **`html-app/`** — Application single-file (Preact + htm), connectée en direct à Supabase (Postgres + Auth + RLS). C'est la version actuellement déployée/testée.
  - `index.html` — l'app complète (UI, logique métier, appels Supabase)
  - `supabase/` — schéma SQL (`schema.sql`), migrations, fonctions Edge (notifications email)
- **`react-app/`** — Version React + Vite du même projet (scaffold initial). À noter : cette version n'a pas encore été resynchronisée avec les dernières fonctionnalités majeures ajoutées côté `html-app` (templates Lean BC/Charter, panneau admin, fiche projet, cost drill-down, etc.).

## Démarrer avec la version HTML (recommandée)

1. Ouvrir `html-app/index.html` dans un navigateur (double-clic ou via un petit serveur statique).
2. Renseigner `SUPABASE_URL` et la clé publique (`anon`/`publishable`) de votre projet Supabase en haut du fichier si vous changez de backend.
3. Exécuter `html-app/supabase/schema.sql` dans l'éditeur SQL de votre projet Supabase pour créer tables, RLS, triggers et fonctions RPC.

## Démarrer avec la version React

```bash
cd react-app
npm install
cp .env.example .env   # renseigner VITE_SUPABASE_URL et VITE_SUPABASE_ANON_KEY
npm run dev
```

## Sécurité

La clé Supabase intégrée dans `html-app/index.html` est la clé **publique** (anon/publishable) — elle est conçue pour être exposée côté client et protégée par les policies RLS définies dans `schema.sql`. La clé `service_role` (utilisée uniquement côté Edge Function pour l'envoi d'emails) n'est jamais codée en dur : elle est lue depuis les variables d'environnement du projet Supabase.
