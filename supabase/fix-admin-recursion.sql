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
