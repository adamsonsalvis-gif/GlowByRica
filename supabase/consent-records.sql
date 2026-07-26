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
