-- Run once in the Supabase SQL Editor (after security-hardening.sql).
-- Stores contact-form enquiries so nothing is lost even if the
-- notification/auto-reply emails fail to send. Written only by the
-- contact-form Edge Function (via the service_role key, which bypasses
-- RLS entirely) - there is no public insert policy.

create table if not exists enquiries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  phone text not null,
  treatment text not null,
  preferred_time text,
  message text not null,
  notify_sent boolean not null default false,
  reply_sent boolean not null default false,
  created_at timestamptz not null default now()
);

alter table enquiries enable row level security;

-- Same pattern as every other table: admin-only, via the SECURITY DEFINER
-- is_admin() helper from security-hardening.sql (avoids the recursion bug
-- an inline "exists (select ... from admin_users)" policy would cause).
create policy "admin only" on enquiries
  for all using (public.is_admin()) with check (public.is_admin());
