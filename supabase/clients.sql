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
