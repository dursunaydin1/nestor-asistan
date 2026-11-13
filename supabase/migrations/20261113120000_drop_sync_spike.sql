-- M1 step 1: the sync spike is done (ADR-0001); its throwaway table and write path go away.
drop function if exists public.spike_upsert(uuid, text, boolean, integer);
drop table if exists public.spike_items;
drop function if exists public.spike_items_touch();
