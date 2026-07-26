-- Run once in the Supabase SQL Editor.
-- Allows the Injectable Treatment Record template in consent_records.

alter table consent_records drop constraint if exists consent_records_template_key_check;
alter table consent_records add constraint consent_records_template_key_check
  check (template_key in ('botox', 'filler', 'hyalase', 'medical', 'treatment'));
