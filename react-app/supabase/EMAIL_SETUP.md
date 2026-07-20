# Notifications email aux porteurs d'idée — mise en place (~30 min)

Principe : à chaque notification insérée en base pour un utilisateur dont le rôle
est `requester`, une Edge Function envoie un email via Resend.
PM / Transformation Team restent en notifications in-app.

## 1. Compte Resend (fournisseur d'email)
1. Crée un compte gratuit sur https://resend.com (100 emails/jour).
2. Récupère une **API key** (Dashboard Resend → API Keys).
3. ⚠️ Important : sans domaine vérifié, Resend n'envoie qu'à TA propre adresse
   (parfait pour tester). Pour envoyer aux vrais employés : Resend → Domains →
   ajoute et vérifie un domaine (2 enregistrements DNS), puis utilise une adresse
   `cockpit@ton-domaine.com` comme expéditeur.

## 2. Edge Function (dans le Dashboard Supabase, sans CLI)
1. Supabase → **Edge Functions** → **Deploy a new function** → nom : `notify-email`.
2. Colle le contenu de `supabase/functions/notify-email/index.ts` → Deploy.
3. Dans l'onglet **Details** de la fonction : désactive **Verify JWT**
   (la sécurité est assurée par le secret d'étape 3).
4. **Edge Functions → Secrets**, ajoute :
   - `RESEND_API_KEY` = ta clé Resend
   - `WEBHOOK_SECRET` = une chaîne aléatoire longue (garde-la pour l'étape 4)
   - `FROM_EMAIL`     = `onboarding@resend.dev` (test) ou ton adresse vérifiée
   - `APP_URL`        = l'URL de l'app (ou laisse vide pour l'instant)

## 3. Webhook base de données
1. Supabase → **Database → Webhooks** → **Create a new hook** :
   - Table : `notifications` · Événement : **Insert**
   - Type : HTTP Request · Méthode : POST
   - URL : l'URL de la fonction (affichée dans Edge Functions, se termine par `/notify-email`)
   - **HTTP Headers** : ajoute `x-webhook-secret` = la même valeur que `WEBHOOK_SECRET`
2. Save.

## 4. Test
1. Connecte-toi avec un compte **requester** dont l'email est TON adresse
   (contrainte Resend sans domaine vérifié).
2. Avec ton compte PM, qualifie une de ses idées → il doit recevoir
   « Your idea IDEA-xxxx has been qualified! » par email.
3. Logs : Supabase → Edge Functions → notify-email → **Logs** en cas de souci.

## Chez le client (plus tard)
Même mécanique, en remplaçant Resend par leur SMTP / Microsoft Graph —
seule la fonction change, ni l'app ni la base.
