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
