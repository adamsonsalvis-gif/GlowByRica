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
  for all using (exists (select 1 from admin_users a where a.user_id = auth.uid()))
  with check (exists (select 1 from admin_users a where a.user_id = auth.uid()));

-- Private bucket
insert into storage.buckets (id, name, public)
values ('patient-photos', 'patient-photos', false)
on conflict (id) do update set public = false;

-- Storage access, admin accounts only
drop policy if exists "admin read patient photos" on storage.objects;
create policy "admin read patient photos" on storage.objects
  for select using (
    bucket_id = 'patient-photos'
    and exists (select 1 from admin_users a where a.user_id = auth.uid())
  );

drop policy if exists "admin upload patient photos" on storage.objects;
create policy "admin upload patient photos" on storage.objects
  for insert with check (
    bucket_id = 'patient-photos'
    and exists (select 1 from admin_users a where a.user_id = auth.uid())
  );

drop policy if exists "admin delete patient photos" on storage.objects;
create policy "admin delete patient photos" on storage.objects
  for delete using (
    bucket_id = 'patient-photos'
    and exists (select 1 from admin_users a where a.user_id = auth.uid())
  );
