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
