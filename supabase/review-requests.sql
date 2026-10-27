-- Run once in the Supabase SQL Editor (after schema.sql).
-- Remembers when a "how was your visit?" review request was emailed for an
-- appointment, so the admin page can show "Review requested" and Rica does not
-- send the same person two by accident.
--
-- Run this BEFORE publishing the matching admin.html change: sending a request
-- writes to this column.

alter table appointments add column if not exists review_requested_at timestamptz;
