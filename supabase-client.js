// Public by design — the anon key only grants what Row Level Security policies
// allow (see supabase/schema.sql). It is safe to ship in client-side code.
const SUPABASE_URL = 'https://kychrharobhmyzuywvpm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt5Y2hyaGFyb2JobXl6dXl3dnBtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5MTU0MDgsImV4cCI6MjA5ODQ5MTQwOH0.ySlyU5tsBT166Kk8j_QuWY5C0PWHImVjalsNcRUnebk';

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
