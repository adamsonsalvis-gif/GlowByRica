-- Run once in the Supabase SQL Editor (after enquiries.sql).
-- Supports the contact-form function's rate limiting.
--
-- ip_hash is a salted one-way SHA-256 of the visitor's IP, never the IP itself
-- (an IP address is personal data). It exists only so the function can tell
-- "the same visitor again" within an hour. The indexes keep those hourly
-- counts fast no matter how large the table grows.

alter table enquiries add column if not exists ip_hash text;

create index if not exists enquiries_created_at_idx on enquiries (created_at desc);
create index if not exists enquiries_email_created_idx on enquiries (email, created_at desc);
create index if not exists enquiries_ip_created_idx on enquiries (ip_hash, created_at desc);
