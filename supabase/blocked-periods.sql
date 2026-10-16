-- Run once in the Supabase SQL Editor (after availability.sql and
-- security-hardening.sql).
--
-- Lets Rica block part of a day - Morning, Afternoon or Evening - instead of
-- only the whole day. Whole days stay in blocked_days exactly as before.
--
-- The website's booking calendar needs no change: get_public_availability()
-- below reports each hour inside a blocked period as already taken, and the
-- picker already greys out a period whose hours are all taken. The hours must
-- match the PERIODS in index.html:
--   morning   9, 10, 11        (9am - 12pm)
--   afternoon 12 - 16          (12pm - 5pm)
--   evening   17 - 21          (5pm - 9pm)

create table if not exists blocked_periods (
  day date not null,
  period text not null check (period in ('morning', 'afternoon', 'evening')),
  created_at timestamptz not null default now(),
  primary key (day, period)
);

alter table blocked_periods enable row level security;

-- Same pattern as every other table: admin only, via is_admin()
drop policy if exists "admin only" on blocked_periods;
create policy "admin only" on blocked_periods
  for all using (public.is_admin()) with check (public.is_admin());

-- Replaces the version from availability.sql (same signature, so the grants
-- below simply re-apply). Still exposes only dates and times - never any
-- client detail. A fully blocked day is returned with a NULL slot.
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
  where day between from_date and to_date
  union all
  select bp.day, make_time(h, 0, 0)
  from blocked_periods bp
  cross join lateral generate_series(
    case bp.period when 'morning' then 9 when 'afternoon' then 12 else 17 end,
    case bp.period when 'morning' then 11 when 'afternoon' then 16 else 21 end
  ) as h
  where bp.day between from_date and to_date;
$$;

revoke all on function public.get_public_availability(date, date) from public;
grant execute on function public.get_public_availability(date, date) to anon, authenticated;
