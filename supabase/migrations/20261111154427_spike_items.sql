-- M0 step 7: sync spike (tech-architecture §10.3, ADR-0001). Throwaway table, dropped in M1.
-- Mirrors the production sync contract: server-assigned version and updated_at, soft deletes,
-- RLS on every row, and a last-write-wins write path that reports overwrites.

create table public.spike_items (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Delta pull: where updated_at > cursor order by updated_at, id
create index spike_items_owner_updated_idx on public.spike_items (owner_id, updated_at, id);

alter table public.spike_items enable row level security;

create policy spike_items_select_own on public.spike_items
  for select to authenticated using (owner_id = (select auth.uid()));
create policy spike_items_insert_own on public.spike_items
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy spike_items_update_own on public.spike_items
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- No public access; rows are never hard-deleted by clients (soft delete via deleted_at)
revoke all on public.spike_items from anon, authenticated;
grant select, insert, update on public.spike_items to authenticated;

-- Clients cannot choose version, updated_at or owner; the server assigns them
create function public.spike_items_touch() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.version := old.version + 1;
    new.owner_id := old.owner_id;
  else
    new.version := 1;
  end if;
  return new;
end;
$$;

create trigger spike_items_touch
  before insert or update on public.spike_items
  for each row execute function public.spike_items_touch();

-- Outbox write path. Last write wins; "overwritten" is true when the server row had moved past
-- the version the client last saw. Security invoker, so RLS applies to every read and write.
create function public.spike_upsert(
  p_id uuid,
  p_title text,
  p_deleted boolean,
  p_base_version integer
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_version integer;
  saved public.spike_items;
begin
  select version into current_version
  from public.spike_items
  where id = p_id
  for update;

  if not found then
    insert into public.spike_items (id, title, deleted_at)
    values (p_id, p_title, case when p_deleted then now() end)
    returning * into saved;
  else
    update public.spike_items
    set title = p_title,
        deleted_at = case when p_deleted then coalesce(deleted_at, now()) end
    where id = p_id
    returning * into saved;
  end if;

  return jsonb_build_object(
    'item', to_jsonb(saved),
    'overwritten', current_version is not null and current_version <> coalesce(p_base_version, 0)
  );
end;
$$;

revoke all on function public.spike_upsert(uuid, text, boolean, integer) from public, anon;
grant execute on function public.spike_upsert(uuid, text, boolean, integer) to authenticated;
