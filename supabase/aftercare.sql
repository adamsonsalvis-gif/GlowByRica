-- Run once in the Supabase SQL Editor.
-- A PRIVATE storage bucket for the aftercare leaflets (PDFs) that the admin page
-- emails to patients from a saved Treatment Record.
--
-- Private on purpose: the leaflets are only ever attached to an email by the
-- appointment-confirmation function (which uses the service key). They are never
-- published on the website, so the product wording in them is not advertised.
--
-- No storage policies are added, so signed-in users cannot read or write this
-- bucket from the browser either - only the function can read it, and files are
-- uploaded from the Supabase dashboard (Storage -> aftercare -> Upload file):
--   dermal-filler-aftercare.pdf
--   anti-wrinkle-aftercare.pdf

insert into storage.buckets (id, name, public)
values ('aftercare', 'aftercare', false)
on conflict (id) do update set public = false;
