// Supabase Edge Function: appointment-confirmation
//
// Called from admin.html when Rica books an appointment with a client email
// on file. Sends the client a branded confirmation of the date, time and
// treatment. Unlike contact-form, this one is NOT public — it stays behind
// normal JWT verification, AND the function itself checks the caller is a
// row in admin_users, because the anon key (which counts as "a valid JWT")
// is public by design and would otherwise let anyone use this as a free
// email relay. Deploy with JWT verification left ON (the default) — do NOT
// untick it the way contact-form needed.
//
// Required secrets: same RESEND_API_KEY and FROM_EMAIL already set for
// contact-form (Project Settings -> Edge Functions -> Secrets). SUPABASE_URL
// and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = Deno.env.get("FROM_EMAIL")!;

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

// Service-role client used both for the admin_users check below and for
// sending mail - never exposed to the browser, only lives in this function.
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

function formatNiceDate(dateStr: string): string {
  const d = new Date(`${dateStr}T00:00:00`);
  return d.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
}

function formatNiceTime(timeStr: string): string {
  const [h, m] = timeStr.split(":").map(Number);
  const period = h >= 12 ? "pm" : "am";
  const hour12 = ((h + 11) % 12) + 1;
  return m ? `${hour12}:${String(m).padStart(2, "0")}${period}` : `${hour12}${period}`;
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

  // Only a logged-in admin account may trigger this - the anon key alone
  // (which any site visitor has) is not enough.
  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: "Not authenticated" }), { status: 401, headers });
  }
  const { data: adminRow } = await supabase
    .from("admin_users")
    .select("user_id")
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (!adminRow) {
    return new Response(JSON.stringify({ error: "Not authorised" }), { status: 403, headers });
  }

  let body: { name?: string; email?: string; treatment?: string; appointment_date?: string; appointment_time?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Bad request" }), { status: 400, headers });
  }

  const name = (body.name || "").trim();
  const email = (body.email || "").trim();
  const treatment = (body.treatment || "").trim();
  const appointment_date = (body.appointment_date || "").trim();
  const appointment_time = (body.appointment_time || "").trim();

  if (!name || !email || !treatment || !appointment_date || !appointment_time) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), { status: 400, headers });
  }
  if (!isValidEmail(email)) {
    return new Response(JSON.stringify({ error: "Invalid email address" }), { status: 400, headers });
  }

  const firstName = name.split(/\s+/)[0] || name;
  const niceDate = formatNiceDate(appointment_date);
  const niceTime = formatNiceTime(appointment_time);
  const LOGO_URL = "https://glowbyrica.com/images/GLOW.png";

  const html = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#FAF3EB; padding:32px 16px;">
      <tr><td align="center">
        <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px; width:100%; background-color:#FFFFFF; border-radius:14px; overflow:hidden; font-family: Georgia, 'Times New Roman', serif;">
          <tr><td style="height:6px; background-color:#C9A463; line-height:6px; font-size:0;">&nbsp;</td></tr>
          <tr><td style="padding:36px 40px 8px 40px; text-align:center;">
            <span style="color:#C9A463; font-size:1.1rem; letter-spacing:0.3em;">✦</span>
          </td></tr>
          <tr><td style="padding:0 40px 32px 40px; color:#3A0D0D; font-size:0.95rem; line-height:1.7;">
            <p style="margin:0 0 1rem 0;">Hi ${escapeHtml(firstName)},</p>
            <p style="margin:0 0 1.4rem 0;">Your consultation with Glow by Rica is confirmed. ✨</p>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#FAF3EB; border-radius:8px; margin:0 0 1.4rem 0;">
              <tr><td style="padding:18px 20px;">
                <p style="margin:0 0 0.6rem 0; color:#C9A463; font-family: Arial, sans-serif; font-size:0.7rem; letter-spacing:0.08em; text-transform:uppercase;">Appointment details</p>
                <p style="margin:0 0 0.3rem 0;"><strong>Date:</strong> ${escapeHtml(niceDate)}</p>
                <p style="margin:0 0 0.3rem 0;"><strong>Time:</strong> ${escapeHtml(niceTime)}</p>
                <p style="margin:0;"><strong>Appointment:</strong> ${escapeHtml(treatment)}</p>
              </td></tr>
            </table>
            <p style="margin:0 0 1rem 0;">During your consultation, we'll take the time to discuss your concerns, what you'd like to achieve, and whether treatment may be suitable for you.</p>
            <p style="margin:0 0 1rem 0;">You'll be asked to complete a short medical history form when you arrive.</p>
            <p style="margin:0 0 1.4rem 0;">There is no obligation to proceed with treatment following your consultation.</p>
            <p style="margin:0 0 0.6rem 0; color:#C9A463; font-family: Arial, sans-serif; font-size:0.7rem; letter-spacing:0.08em; text-transform:uppercase;">Finding the clinic</p>
            <p style="margin:0 0 1.4rem 0;">Glow by Rica<br>Suite 115, Phenix Salon<br>Springwell Square<br>Derby, DE1 1FB</p>
            <p style="margin:0 0 1.4rem 0;">If you need to cancel or reschedule your consultation, please let us know at least 24 hours before your appointment.</p>
            <p style="margin:0 0 1.4rem 0;">We look forward to welcoming you to Glow by Rica.</p>
            <p style="margin:0;">Warmly,<br><strong style="color:#C9A463;">Rica</strong><br>Registered Nurse<br>Glow by Rica</p>
          </td></tr>
          <tr><td style="padding:0 40px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
              <td style="border-top:1px solid rgba(201,164,99,0.35); line-height:1px; font-size:0;">&nbsp;</td>
            </tr></table>
          </td></tr>
          <tr><td style="padding:24px 40px 36px 40px; text-align:center;">
            <img src="${LOGO_URL}" alt="Glow By Rica" width="110" style="width:110px; max-width:110px; height:auto; display:inline-block;">
            <p style="margin:14px 0 0 0; font-family: Arial, sans-serif; font-size:0.7rem; letter-spacing:0.05em; color:rgba(58,13,13,0.55);">
              Phenix Salon Suites, Derby City Centre &nbsp;·&nbsp; <a href="https://glowbyrica.com" style="color:#C9A463; text-decoration:none;">glowbyrica.com</a>
            </p>
          </td></tr>
        </table>
      </td></tr>
    </table>`;

  const emailRes = await sendEmail(email, "Your consultation is confirmed - Glow by Rica", html, "rica@glowbyrica.com");
  if (!emailRes.ok) {
    console.error("appointment-confirmation: email failed", await emailRes.text());
    return new Response(JSON.stringify({ error: "Could not send email" }), { status: 502, headers });
  }

  return new Response(JSON.stringify({ ok: true }), { status: 200, headers });
});
