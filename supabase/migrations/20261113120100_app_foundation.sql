-- M1 step 1: extensions, the private `app` schema, Turkish text helpers and shared triggers
-- (data-model §8.1, tech-architecture §10.3). No tables yet; later migrations attach these.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

-- Helpers used by policies and triggers. Not exposed through the API; anon gets nothing.
create schema app;
revoke all on schema app from public, anon;
grant usage on schema app to authenticated, service_role;
alter default privileges in schema app revoke execute on functions from public;

-- Turkish lowercase. lower() alone maps "I" to "i" and, under a C collation, leaves non-ASCII
-- letters untouched, so the Turkish capitals are translated first. Must match the client's
-- toLocaleLowerCase('tr-TR'); both sides are tested with the same cases.
create function app.tr_lower(value text) returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(translate(normalize(value, NFC), 'IİŞĞÜÖÇÂÎÛ', 'ıişğüöçâîû'))
$$;

-- Server twin of normalizeTr() in packages/shared/src/text.ts: NFC, trim, single spaces, tr_lower
create function app.normalize_tr(value text) returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select app.tr_lower(btrim(regexp_replace(value, '\s+', ' ', 'g')))
$$;

-- search_text column value from any number of fields; nulls are skipped
create function app.search_text(variadic parts text[]) returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select app.normalize_tr(array_to_string(parts, ' '))
$$;

grant execute on function app.tr_lower(text), app.normalize_tr(text), app.search_text(text[])
  to authenticated, service_role;

-- Synced tables: the server owns created_*, updated_*, and version; client values are ignored
-- so last-write-wins and "overwritten" detection can trust them (ADR-0001).
create function app.touch_row() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'INSERT' then
    new.created_at := new.updated_at;
    new.created_by := new.updated_by;
    new.version := 1;
  else
    new.created_at := old.created_at;
    new.created_by := old.created_by;
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

-- Child tables of a person-owned record carry the parent's kaydeden_user_id so RLS needs no join
-- (data-model §3, rule 3). Whatever the client sends is replaced from the parent.
-- Usage: execute function app.copy_parent_owner('public.persons', 'person_id')
-- Runs as the caller, so a parent hidden by RLS yields null and the not-null column rejects it.
create function app.copy_parent_owner() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  parent_id uuid := (to_jsonb(new) ->> tg_argv[1])::uuid;
  owner_id uuid;
begin
  execute format('select kaydeden_user_id from %s where id = $1', tg_argv[0]::regclass)
    into owner_id
    using parent_id;
  new.kaydeden_user_id := owner_id;
  return new;
end;
$$;

-- Belt and braces in case platform-wide default privileges granted anything above
revoke execute on all functions in schema app from public, anon;
