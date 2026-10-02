-- Run once in the Supabase SQL Editor (after schema.sql).
-- Remembers the client's email on the appointment itself, so rescheduling
-- can offer to email them without asking for the address a second time.
--
-- Run this BEFORE publishing the matching admin.html change: the new booking
-- form writes to this column, and saving an appointment would fail without it.
--
-- Not exposed publicly: get_public_availability() returns only dates and times.

alter table appointments add column if not exists client_email text;
