-- Supabase's platform-wide default privileges grant EXECUTE on every new function to anon, and a
-- per-schema default cannot take that away. Functions created in step 2 inherited it (the anon
-- guard test caught it). anon has no USAGE on app, so nothing was callable; this restores the
-- second line of defence. Every migration that adds functions ends with these revokes.
revoke execute on all functions in schema app from public, anon;
revoke execute on function public.list_org_members() from public, anon;
