// Supabase Edge Function: contact-form
//
// Replaces Formspree for the main-page contact form. On each submission it:
//   1. Saves the enquiry to the `enquiries` table (see supabase/enquiries.sql),
//      so nothing is lost even if the emails below fail.
//   2. Emails Rica a notification with the enquiry details.
//   3. Emails the client an auto-reply confirming receipt (NOT a confirmed
//      booking - Rica still agrees the exact time by hand).
//
// Spam protection (this endpoint is public, and the auto-reply would
// otherwise let a bot make us email any address it likes):
//   - Honeypot: a hidden "fax_number" field. Bots fill it, humans can't
//     see it. Filled => pretend success, send nothing, store nothing.
//   - Timing: the page stamps "form_started_at". Missing, absurd, or under
//     MIN_FILL_MS old => rejected.
//   - Rate limits, counted from accepted rows in `enquiries` over the last
//     hour: per email, per IP (stored only as a salted hash), and overall.
//     Needs supabase/enquiries-spam-protection.sql run once.
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

// Anti-spam tuning. Real enquiries are a handful a week, so these are generous
// for people and tight for bots. Resend's free tier is 100 emails/day and each
// enquiry sends two, which is why there is an overall cap too.
const MIN_FILL_MS = 3_000;               // nobody completes this form faster
const MAX_FORM_AGE_MS = 7 * 24 * 3600_000; // a tab left open for a week => ask to refresh
const WINDOW_MS = 3600_000;
const LIMIT_PER_EMAIL = 3;
const LIMIT_PER_IP = 5;
const LIMIT_OVERALL = 20;

const MAX_LEN = { name: 100, email: 254, phone: 40, treatment: 100, preferred_time: 100, message: 3000 };

// Cloudflare fronts Supabase and sets cf-connecting-ip itself, so it can't be
// spoofed by the client the way a leftmost x-forwarded-for entry can.
function clientIp(req: Request): string | null {
  return req.headers.get("cf-connecting-ip")
    ?? req.headers.get("x-forwarded-for")?.split(",")[0].trim()
    ?? null;
}

// We never store the raw IP (personal data) - only a salted one-way hash, which
// is enough to count "same visitor" for rate limiting. The service key is
// already a secret only this function holds, so it doubles as the salt.
async function hashIp(ip: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${ip}:${SERVICE_ROLE_KEY}`));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function recentCount(column: "email" | "ip_hash" | null, value: string | null, since: string): Promise<number> {
  let q = supabase.from("enquiries").select("id", { count: "exact", head: true }).gte("created_at", since);
  if (column && value) q = q.eq(column, value);
  const { count, error } = await q;
  if (error) {
    // Fail open: a database hiccup shouldn't lock real clients out.
    console.error("contact-form: rate limit lookup failed", error);
    return 0;
  }
  return count ?? 0;
}

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
  let honeypot = "", startedAtRaw = "";
  try {
    const form = await req.formData();
    name = String(form.get("name") || "").trim();
    // Lower-cased so the per-email rate limit can't be dodged with "A@x.com" vs "a@x.com".
    email = String(form.get("email") || "").trim().toLowerCase();
    phone = String(form.get("phone") || "").trim();
    treatment = String(form.get("treatment") || "").trim();
    preferred_time = String(form.get("preferred_time") || "").trim();
    message = String(form.get("message") || "").trim();
    honeypot = String(form.get("fax_number") || "").trim();
    startedAtRaw = String(form.get("form_started_at") || "").trim();
  } catch (err) {
    console.error("contact-form: could not parse form data", err);
    return new Response(JSON.stringify({ error: "Bad request" }), { status: 400, headers });
  }

  // 1. Honeypot. Answer "success" so the bot learns nothing, but do nothing.
  if (honeypot) {
    console.warn("contact-form: honeypot tripped, dropping submission");
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers });
  }

  // 2. Timing. A visible message here, because a real person on a stale cached
  // copy of the page (no stamp yet) can hit it and just needs to refresh.
  const startedAt = Number(startedAtRaw);
  const age = Date.now() - startedAt;
  if (!startedAtRaw || !Number.isFinite(startedAt) || age < 0 || age > MAX_FORM_AGE_MS) {
    return new Response(JSON.stringify({ error: "Please refresh the page and try sending your message again." }), { status: 400, headers });
  }
  if (age < MIN_FILL_MS) {
    return new Response(JSON.stringify({ error: "That was very quick - please take a moment and try again." }), { status: 400, headers });
  }

  if (!name || !email || !phone || !treatment || !message) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), { status: 400, headers });
  }
  if (!isValidEmail(email)) {
    return new Response(JSON.stringify({ error: "Invalid email address" }), { status: 400, headers });
  }
  if (name.length > MAX_LEN.name || email.length > MAX_LEN.email || phone.length > MAX_LEN.phone ||
      treatment.length > MAX_LEN.treatment || preferred_time.length > MAX_LEN.preferred_time ||
      message.length > MAX_LEN.message) {
    return new Response(JSON.stringify({ error: "One of your answers is too long - please shorten it and try again." }), { status: 400, headers });
  }

  // 3. Rate limits.
  const ip = clientIp(req);
  const ip_hash = ip ? await hashIp(ip) : null;
  const since = new Date(Date.now() - WINDOW_MS).toISOString();
  const [byEmail, byIp, overall] = await Promise.all([
    recentCount("email", email, since),
    ip_hash ? recentCount("ip_hash", ip_hash, since) : Promise.resolve(0),
    recentCount(null, null, since),
  ]);
  if (byEmail >= LIMIT_PER_EMAIL || byIp >= LIMIT_PER_IP) {
    return new Response(JSON.stringify({ error: "You've sent a few messages recently. Please wait a little while before trying again, or email rica@glowbyrica.com." }), { status: 429, headers });
  }
  if (overall >= LIMIT_OVERALL) {
    console.warn("contact-form: overall hourly cap reached");
    return new Response(JSON.stringify({ error: "We're receiving a lot of messages right now. Please email rica@glowbyrica.com directly." }), { status: 429, headers });
  }

  const { data: inserted, error: dbError } = await supabase
    .from("enquiries")
    .insert({ name, email, phone, treatment, preferred_time, message, ip_hash })
    .select("id")
    .single();

  if (dbError) {
    console.error("contact-form: db insert failed", dbError);
  }

  // Shared branded wrapper (table-based for compatibility with Outlook/older
  // clients, not just modern webmail). `bodyHtml` is dropped into the cream
  // card; `showLogo` puts the GLOW mark centred beneath the signature.
  const LOGO_URL = "https://glowbyrica.com/images/GLOW.png";
  const emailShell = (bodyHtml: string, showLogo: boolean) => `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#FAF3EB; padding:32px 16px;">
      <tr><td align="center">
        <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px; width:100%; background-color:#FFFFFF; border-radius:14px; overflow:hidden; font-family: Georgia, 'Times New Roman', serif;">
          <tr><td style="height:6px; background-color:#C9A463; line-height:6px; font-size:0;">&nbsp;</td></tr>
          <tr><td style="padding:36px 40px 8px 40px; text-align:center;">
            <span style="color:#C9A463; font-size:1.1rem; letter-spacing:0.3em;">✦</span>
          </td></tr>
          <tr><td style="padding:0 40px 32px 40px; color:#3A0D0D; font-size:0.95rem; line-height:1.7;">
            ${bodyHtml}
          </td></tr>
          ${showLogo ? `
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
          </td></tr>` : ""}
        </table>
      </td></tr>
    </table>`;

  const notifyHtml = emailShell(`
      <h2 style="color:#C9A463; font-size:1.15rem; margin:0 0 1rem 0; text-align:center;">New enquiry from the website</h2>
      <p style="margin:0 0 0.5rem 0;"><strong>Name:</strong> ${escapeHtml(name)}</p>
      <p style="margin:0 0 0.5rem 0;"><strong>Email:</strong> ${escapeHtml(email)}</p>
      <p style="margin:0 0 0.5rem 0;"><strong>Phone:</strong> ${escapeHtml(phone)}</p>
      <p style="margin:0 0 0.5rem 0;"><strong>Treatment:</strong> ${escapeHtml(treatment)}</p>
      <p style="margin:0 0 0.5rem 0;"><strong>Preferred time:</strong> ${escapeHtml(preferred_time || "Not specified")}</p>
      <p style="margin:1rem 0 0 0;"><strong>Message:</strong><br>${escapeHtml(message).replace(/\n/g, "<br>")}</p>
  `, false);

  const firstName = name.split(/\s+/)[0] || name;

  const replyHtml = emailShell(`
      <h1 style="color:#3A0D0D; font-size:1.3rem; font-weight:normal; margin:0 0 1.2rem 0; text-align:center;">Thank you for contacting<br>Glow by Rica ✨</h1>
      <p style="margin:0 0 1rem 0;">Hi ${escapeHtml(firstName)},</p>
      <p style="margin:0 0 1rem 0;">We've received your enquiry and will be in touch within 24 hours.</p>
      <p style="margin:0 0 1rem 0;">Glow by Rica is a nurse-led aesthetics clinic based at Phenix Salon Suites in Derby City Centre.</p>
      <p style="margin:0 0 1.6rem 0;">Our approach is consultation-led, with treatments tailored to you and focused on natural-looking results.</p>
      <p style="margin:0;">Warmly,<br><strong style="color:#C9A463;">Rica</strong><br>Registered Nurse | Glow by Rica</p>
  `, true);

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
