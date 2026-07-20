// Supabase Edge Function: notify-email
// Triggered by a Database Webhook on INSERT into public.notifications.
// Sends an email (via Resend) to the recipient ONLY if their role is 'requester'
// — idea owners get emailed at key steps; PM/Transformation Team stay in-app.

import { createClient } from "npm:@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") ?? "onboarding@resend.dev";
const APP_URL = Deno.env.get("APP_URL") ?? "";

Deno.serve(async (req) => {
  // Authenticate the webhook call (configure the same header in the Dashboard webhook)
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await req.json();
  if (payload.type !== "INSERT" || payload.table !== "notifications") {
    return new Response("Ignored", { status: 200 });
  }
  const n = payload.record;

  // Look up the recipient with the service role (bypasses RLS)
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: profile, error } = await admin
    .from("profiles").select("name, email, role, active")
    .eq("id", n.recipient_id).single();

  if (error || !profile) return new Response("No profile", { status: 200 });
  if (profile.role !== "requester" || !profile.active) {
    return new Response("Skipped (in-app only for this role)", { status: 200 });
  }

  const subject = `[Digitalization Program] ${n.type}${n.related_id ? " — " + n.related_id : ""}`;
  const html = `
    <div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#1a2233">
      <p>Hello ${profile.name || ""},</p>
      <p>${n.message}</p>
      ${APP_URL ? `<p><a href="${APP_URL}" style="background:#1f4fd8;color:#fff;padding:8px 16px;border-radius:6px;text-decoration:none">Open the Digitalization Cockpit</a></p>` : ""}
      <p style="color:#66708a;font-size:12px">You receive this email because you submitted an idea to the PWT Digitalization Program. Follow the full status anytime in the app.</p>
    </div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${RESEND_API_KEY}` },
    body: JSON.stringify({ from: FROM_EMAIL, to: profile.email, subject, html }),
  });

  return new Response(res.ok ? "Sent" : `Resend error: ${await res.text()}`, {
    status: res.ok ? 200 : 500,
  });
});
