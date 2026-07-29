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
