-- Glow By Rica: full schema, all migrations in order.
-- Paste this whole file into the Supabase SQL Editor and run once.
-- Intended for building a fresh project (e.g. a restore rehearsal).
-- Generated from the individual files - edit those, not this.


-- ============================================================
-- schema.sql
-- ============================================================
-- Run this once in the Supabase SQL Editor (Project > SQL Editor > New query)

create table if not exists appointments (
  id uuid primary key default gen_random_uuid(),
  client_name text not null,
  treatment text not null,
  appointment_date date not null,
  appointment_time time not null,
  price numeric(10,2),
  status text not null default 'confirmed' check (status in ('confirmed', 'pending', 'cancelled')),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists consent_forms (
  id uuid primary key default gen_random_uuid(),
  client_name text not null,
  template_name text not null,
  status text not null default 'pending' check (status in ('pending', 'signed', 'expired')),
  submitted_at timestamptz,
  created_at timestamptz not null default now()
);

alter table appointments enable row level security;
alter table consent_forms enable row level security;

-- Only her logged-in account can read/write — there is no public sign-up,
-- so "authenticated" effectively means "the clinic owner".
create policy "authenticated full access" on appointments
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "authenticated full access" on consent_forms
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- ============================================================
-- availability.sql
-- ============================================================
-- Run once in the Supabase SQL Editor (after schema.sql).
-- Adds day-blocking for the admin calendar and a public availability
-- feed for the booking date/time picker on the main page.

create table if not exists blocked_days (
  day date primary key,
  note text,
  created_at timestamptz not null default now()
);

alter table blocked_days enable row level security;

create policy "authenticated full access" on blocked_days
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- Public availability: exposes ONLY which slots are taken / days blocked.
-- No client names or details ever leave the database via this function.
-- A blocked day is returned with a NULL slot.
create or replace function public.get_public_availability(from_date date, to_date date)
returns table (day date, slot time)
language sql
security definer
set search_path = public
as $$
  select appointment_date as day, appointment_time as slot
  from appointments
  where appointment_date between from_date and to_date
    and status <> 'cancelled'
  union all
  select day, null::time
  from blocked_days
  where day between from_date and to_date;
$$;

revoke all on function public.get_public_availability(date, date) from public;
grant execute on function public.get_public_availability(date, date) to anon, authenticated;

-- ============================================================
-- consent-records.sql
-- ============================================================
-- Run once in the Supabase SQL Editor.
-- Completed consent forms filled in on the admin portal (iPad, in-room).
-- All field values, ticked boxes and signature images (PNG data URLs)
-- live in the data jsonb column.

create table if not exists consent_records (
  id uuid primary key default gen_random_uuid(),
  template_key text not null check (template_key in ('botox', 'filler', 'hyalase')),
  client_name text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table consent_records enable row level security;

create policy "authenticated full access" on consent_records
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- ============================================================
-- medical-history.sql
-- ============================================================
-- Run once in the Supabase SQL Editor.
-- Allows the Medical History template in consent_records.

alter table consent_records drop constraint if exists consent_records_template_key_check;
alter table consent_records add constraint consent_records_template_key_check
  check (template_key in ('botox', 'filler', 'hyalase', 'medical'));

-- ============================================================
-- clients.sql
-- ============================================================
-- Run once in the Supabase SQL Editor.
-- Standalone client profiles: created manually from the Clients tab or
-- auto-registered when a form is saved for a new name.

create table if not exists clients (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  phone text,
  email text,
  created_at timestamptz not null default now()
);

alter table clients enable row level security;

create policy "authenticated full access" on clients
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- ============================================================
-- treatment-record.sql
-- ============================================================
-- Run once in the Supabase SQL Editor.
-- Allows the Injectable Treatment Record template in consent_records.

alter table consent_records drop constraint if exists consent_records_template_key_check;
alter table consent_records add constraint consent_records_template_key_check
  check (template_key in ('botox', 'filler', 'hyalase', 'medical', 'treatment'));

-- ============================================================
-- security-hardening.sql
-- ============================================================
-- Run once in the Supabase SQL Editor.
--
-- WHY: the existing policies grant access to ANY authenticated user
-- (auth.role() = 'authenticated'). The anon key is public by design (it
-- ships in the site's JS), so if signup is ever open, a stranger could
-- register an account and read every appointment, client and consent
-- record. This restricts access to named admin accounts instead.

create table if not exists admin_users (
  user_id uuid primary key,
  note text,
  added_at timestamptz not null default now()
);

alter table admin_users enable row level security;

-- Seed with the accounts that exist right now (i.e. Rica's login).
-- Anyone who signs up later is NOT added, so they get nothing.
insert into admin_users (user_id, note)
select id, email from auth.users
on conflict (user_id) do nothing;

-- Membership check runs in a SECURITY DEFINER function so policies never
-- re-enter admin_users (which would be infinite recursion).
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from admin_users where user_id = auth.uid()) $$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Non-recursive: you may read your own admin row
drop policy if exists "own admin row" on admin_users;
create policy "own admin row" on admin_users
  for select using (user_id = auth.uid());

-- Swap every table over to admin-only access
drop policy if exists "authenticated full access" on appointments;
create policy "admin only" on appointments
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "authenticated full access" on consent_forms;
create policy "admin only" on consent_forms
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "authenticated full access" on consent_records;
create policy "admin only" on consent_records
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "authenticated full access" on blocked_days;
create policy "admin only" on blocked_days
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "authenticated full access" on clients;
create policy "admin only" on clients
  for all using (public.is_admin()) with check (public.is_admin());

-- Sanity check: should list exactly the intended admin account(s)
select u.email, a.added_at from admin_users a join auth.users u on u.id = a.user_id;

-- ============================================================
-- fix-admin-recursion.sql
-- ============================================================
-- Run once in the Supabase SQL Editor. Fixes:
--   "infinite recursion detected in policy for relation admin_users"
--
-- Cause: policies checked membership with a subquery on admin_users, and
-- admin_users' own SELECT policy did the same, so evaluating it required
-- evaluating it. Postgres detects the loop and aborts.
--
-- Fix: do the lookup inside a SECURITY DEFINER function, which runs as the
-- function owner with RLS bypassed, so the check never re-enters a policy.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from admin_users where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- admin_users: non-recursive policy (you may read your own row)
drop policy if exists "admins read admin list" on admin_users;
drop policy if exists "own admin row" on admin_users;
create policy "own admin row" on admin_users
  for select using (user_id = auth.uid());

-- Data tables now go through the function
drop policy if exists "admin only" on appointments;
create policy "admin only" on appointments
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin only" on consent_forms;
create policy "admin only" on consent_forms
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin only" on consent_records;
create policy "admin only" on consent_records
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin only" on blocked_days;
create policy "admin only" on blocked_days
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin only" on clients;
create policy "admin only" on clients
  for all using (public.is_admin()) with check (public.is_admin());

-- client_photos only exists once client-photos.sql has been run
do $$
begin
  if to_regclass('public.client_photos') is not null then
    execute 'drop policy if exists "admin only" on client_photos';
    execute 'create policy "admin only" on client_photos for all using (public.is_admin()) with check (public.is_admin())';
  end if;
end $$;

-- Storage policies had the same recursive lookup
drop policy if exists "admin read patient photos" on storage.objects;
create policy "admin read patient photos" on storage.objects
  for select using (bucket_id = 'patient-photos' and public.is_admin());

drop policy if exists "admin upload patient photos" on storage.objects;
create policy "admin upload patient photos" on storage.objects
  for insert with check (bucket_id = 'patient-photos' and public.is_admin());

drop policy if exists "admin delete patient photos" on storage.objects;
create policy "admin delete patient photos" on storage.objects
  for delete using (bucket_id = 'patient-photos' and public.is_admin());

-- Should return true while you are signed in as the admin
select public.is_admin() as i_am_admin;

-- ============================================================
-- client-photos.sql
-- ============================================================
-- Run once in the Supabase SQL Editor (after security-hardening.sql).
-- Before/after photos attached to a client profile.
--
-- Patient photographs are special category data, so the bucket is PRIVATE:
-- files are never served from a public URL, only through short-lived signed
-- links generated for a logged-in admin.

create table if not exists client_photos (
  id uuid primary key default gen_random_uuid(),
  client_name text not null,
  path text not null,
  kind text not null check (kind in ('before', 'after')),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists client_photos_client_idx on client_photos (client_name);

alter table client_photos enable row level security;

drop policy if exists "admin only" on client_photos;
create policy "admin only" on client_photos
  for all using (public.is_admin()) with check (public.is_admin());

-- Private bucket
insert into storage.buckets (id, name, public)
values ('patient-photos', 'patient-photos', false)
on conflict (id) do update set public = false;

-- Storage access, admin accounts only
drop policy if exists "admin read patient photos" on storage.objects;
create policy "admin read patient photos" on storage.objects
  for select using (
    bucket_id = 'patient-photos'
    and public.is_admin()
  );

drop policy if exists "admin upload patient photos" on storage.objects;
create policy "admin upload patient photos" on storage.objects
  for insert with check (
    bucket_id = 'patient-photos'
    and public.is_admin()
  );

drop policy if exists "admin delete patient photos" on storage.objects;
create policy "admin delete patient photos" on storage.objects
  for delete using (
    bucket_id = 'patient-photos'
    and public.is_admin()
  );
