// Supabase Edge Function: contact-form
//
// Replaces Formspree for the main-page contact form. On each submission it:
//   1. Saves the enquiry to the `enquiries` table (see supabase/enquiries.sql),
//      so nothing is lost even if the emails below fail.
//   2. Emails Rica a notification with the enquiry details.
//   3. Emails the client an auto-reply confirming receipt (NOT a confirmed
//      booking - Rica still agrees the exact time by hand).
//
// Deploy with JWT verification turned OFF - this must be reachable by
// anonymous site visitors with no Supabase session. In the dashboard:
// Edge Functions -> contact-form -> untick "Enforce JWT verification".
// Via the CLI: supabase functions deploy contact-form --no-verify-jwt
//
// Required secrets (Project Settings -> Edge Functions -> Secrets, or
// `supabase secrets set NAME=value`). SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are injected automatically by the platform -
// do NOT set those yourself.
//   RESEND_API_KEY   - from resend.com, after verifying glowbyrica.com
//   NOTIFY_EMAIL      - where enquiries land, e.g. rica@glowbyrica.com
//   FROM_EMAIL        - verified sender, e.g. "Glow By Rica <hello@glowbyrica.com>"

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const NOTIFY_EMAIL = Deno.env.get("NOTIFY_EMAIL")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL")!;

// Only these origins may call this function from a browser.
const ALLOWED_ORIGINS = new Set([
  "https://glowbyrica.com",
  "https://www.glowbyrica.com",
]);

function corsHeaders(origin: string | null): HeadersInit {
  return {
    "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://glowbyrica.com",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, accept",
    "Vary": "Origin",
  };
}

const escapeHtml = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const isValidEmail = (s: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function sendEmail(to: string, subject: string, html: string, replyTo?: string) {
  return fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to,
      subject,
      html,
      ...(replyTo ? { reply_to: replyTo } : {}),
    }),
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  const headers = corsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response(null, { headers });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers });
  }

  let name = "", email = "", phone = "", treatment = "", preferred_time = "", message = "";
  try {
    const form = await req.formData();
    name = String(form.get("name") || "").trim();
    email = String(form.get("email") || "").trim();
    phone = String(form.get("phone") || "").trim();
    treatment = String(form.get("treatment") || "").trim();
    preferred_time = String(form.get("preferred_time") || "").trim();
    message = String(form.get("message") || "").trim();
  } catch (err) {
    console.error("contact-form: could not parse form data", err);
    return new Response(JSON.stringify({ error: "Bad request" }), { status: 400, headers });
  }

  if (!name || !email || !phone || !treatment || !message) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), { status: 400, headers });
  }
  if (!isValidEmail(email)) {
    return new Response(JSON.stringify({ error: "Invalid email address" }), { status: 400, headers });
  }

  const { data: inserted, error: dbError } = await supabase
    .from("enquiries")
    .insert({ name, email, phone, treatment, preferred_time, message })
    .select("id")
    .single();

  if (dbError) {
    console.error("contact-form: db insert failed", dbError);
  }

  const notifyHtml = `
    <div style="font-family: Georgia, serif; color:#3A0D0D;">
      <h2 style="color:#C9A463;">New enquiry from the website</h2>
      <p><strong>Name:</strong> ${escapeHtml(name)}</p>
      <p><strong>Email:</strong> ${escapeHtml(email)}</p>
      <p><strong>Phone:</strong> ${escapeHtml(phone)}</p>
      <p><strong>Treatment:</strong> ${escapeHtml(treatment)}</p>
      <p><strong>Preferred time:</strong> ${escapeHtml(preferred_time || "Not specified")}</p>
      <p><strong>Message:</strong><br>${escapeHtml(message).replace(/\n/g, "<br>")}</p>
    </div>`;

  const firstName = name.split(/\s+/)[0] || name;

  const replyHtml = `
    <div style="font-family: Georgia, serif; color:#3A0D0D; max-width:480px; margin:0 auto; line-height:1.6;">
      <p>Hi ${escapeHtml(firstName)},</p>
      <p>Thank you for contacting Glow by Rica ✨</p>
      <p>We've received your enquiry and will be in touch within 24 hours.</p>
      <p>Glow by Rica is a nurse-led aesthetics clinic based at Phenix Salon Suites in Derby City Centre.</p>
      <p>Our approach is consultation-led, with treatments tailored to you and focused on natural-looking results.</p>
      <p style="margin-top:2rem;">Warmly,<br><strong style="color:#C9A463;">Rica</strong><br>Registered Nurse | Glow by Rica</p>
    </div>`;

  const [notifyRes, replyRes] = await Promise.all([
    sendEmail(NOTIFY_EMAIL, `New enquiry - ${name}`, notifyHtml, email),
    sendEmail(email, "Thank you for contacting Glow by Rica", replyHtml, "rica@glowbyrica.com"),
  ]);

  const notifyOk = notifyRes.ok;
  const replyOk = replyRes.ok;
  if (!notifyOk) console.error("contact-form: notify email failed", await notifyRes.text());
  if (!replyOk) console.error("contact-form: auto-reply email failed", await replyRes.text());

  if (inserted?.id) {
    await supabase.from("enquiries").update({ notify_sent: notifyOk, reply_sent: replyOk }).eq("id", inserted.id);
  }

  // Only fail the whole request if we neither saved the enquiry nor
  // managed to notify Rica - otherwise the enquiry isn't actually lost.
  if (dbError && !notifyOk) {
    return new Response(JSON.stringify({ error: "Could not process enquiry" }), { status: 500, headers });
  }

  return new Response(JSON.stringify({ ok: true }), { status: 200, headers });
});
