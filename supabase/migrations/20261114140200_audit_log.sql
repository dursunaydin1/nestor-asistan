-- M1 step 8: change log (FR-ADM-03, data-model §8.3). A generic trigger records who changed what,
-- when, and the before/after of the changed fields only. Admins read it; nobody writes it directly.
-- Personal data in before/after is anonymised with the person (FR-PER-06, step 10).

create table public.audit_log (
  id bigint generated always as identity primary key,
  -- No foreign key: rows are written while an office's data is being cascaded away; the
  -- closing job (FR-ORG-05) removes them by org_id
  org_id uuid not null,
  user_id uuid,
  action text not null check (action in ('insert', 'update', 'delete')),
  table_name text not null,
  row_id uuid,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_row_idx on public.audit_log (org_id, table_name, row_id, created_at);
create index audit_log_org_idx on public.audit_log (org_id, created_at desc);

create function app.audit_row() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_row jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  new_row jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  -- Bookkeeping columns that change on every write and say nothing new
  noise text[] := array['created_at', 'created_by', 'updated_at', 'updated_by', 'version', 'search_text'];
  before_data jsonb := '{}'::jsonb;
  after_data jsonb := '{}'::jsonb;
  key text;
begin
  if tg_op = 'UPDATE' then
    for key in select jsonb_object_keys(new_row) loop
      if not key = any (noise) and (old_row -> key) is distinct from (new_row -> key) then
        before_data := before_data || jsonb_build_object(key, old_row -> key);
        after_data := after_data || jsonb_build_object(key, new_row -> key);
      end if;
    end loop;
    if after_data = '{}'::jsonb then
      return null;
    end if;
  end if;

  insert into public.audit_log (org_id, user_id, action, table_name, row_id, before, after)
  values (
    (case when tg_table_name = 'organizations' then row_data ->> 'id' else row_data ->> 'org_id' end)::uuid,
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    (row_data ->> 'id')::uuid,
    case tg_op when 'INSERT' then null when 'UPDATE' then before_data else old_row - noise end,
    case tg_op when 'DELETE' then null when 'UPDATE' then after_data else new_row - noise end
  );
  return null;
end;
$$;

-- Critical tables (FR-ADM-03: price, status, owner, deletion included)
create trigger audit after update on public.organizations
  for each row execute function app.audit_row();
create trigger audit after insert or update or delete on public.profiles
  for each row execute function app.audit_row();
create trigger audit after insert or update or delete on public.invitations
  for each row execute function app.audit_row();
create trigger audit after insert or update or delete on public.persons
  for each row execute function app.audit_row();
create trigger audit after insert or update or delete on public.requests
  for each row execute function app.audit_row();
create trigger audit after insert or update or delete on public.properties
  for each row execute function app.audit_row();
create trigger audit after insert or update or delete on public.property_private
  for each row execute function app.audit_row();
create trigger audit after insert or update or delete on public.property_owners
  for each row execute function app.audit_row();

revoke all on public.audit_log from anon, authenticated;
alter table public.audit_log enable row level security;

-- Admins only (PRD §6); no client role may insert, update or delete
grant select on public.audit_log to authenticated;
create policy audit_log_select_admin on public.audit_log
  for select to authenticated
  using (org_id = (select app.current_org_id()) and (select app.is_admin()));

-- Platform-wide defaults grant EXECUTE on new functions to anon (see 20261113140100)
revoke execute on all functions in schema app from public, anon;
