-- M1 step 2: plans, offices, profiles, invitations, usage counters, RLS helpers and op-id
-- de-duplication (data-model §8.2–8.3, ADR-0001, ADR-0005). Sign-up, invites and role changes
-- are server-side functions in M2; clients get no insert path here.

-- ADR-0005: English identifiers; person-owned child rows carry owner_id
create or replace function app.copy_parent_owner() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  parent_id uuid := (to_jsonb(new) ->> tg_argv[1])::uuid;
  parent_owner uuid;
begin
  execute format('select owner_id from %s where id = $1', tg_argv[0]::regclass)
    into parent_owner
    using parent_id;
  new.owner_id := parent_owner;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

-- PRD §7.16; null limit = unlimited. Display names live in tr.json.
create table public.plans (
  id text primary key check (id ~ '^[a-z_]+$'),
  limits jsonb not null default '{}'::jsonb check (jsonb_typeof(limits) = 'object')
);

insert into public.plans (id, limits) values
  ('free', '{"max_users": 1, "max_properties": 30, "max_requests": 30, "max_photos_per_property": 5, "max_videos_per_property": 0, "ai_requests_per_user_month": 30, "forms_per_month": 10}'),
  ('standard', '{"max_users": 5, "max_properties": 300, "max_requests": 300, "max_photos_per_property": 15, "max_videos_per_property": 1, "ai_requests_per_user_month": 300, "forms_per_month": null}'),
  ('pro', '{"max_users": 20, "max_properties": 2000, "max_requests": 2000, "max_photos_per_property": 15, "max_videos_per_property": 1, "ai_requests_per_user_month": 1000, "forms_per_month": null}');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 200),
  legal_name text check (char_length(legal_name) <= 300),
  license_no text check (char_length(license_no) <= 50),
  logo_path text check (char_length(logo_path) <= 500),
  brand_color text check (brand_color ~ '^#[0-9A-Fa-f]{6}$'),
  contact jsonb not null default '{}'::jsonb check (jsonb_typeof(contact) = 'object'),
  signature_text text check (char_length(signature_text) <= 2000),
  settings jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object'),
  plan_id text not null default 'free' references public.plans (id),
  status text not null default 'active' check (status in ('active', 'suspended', 'closing')),
  closing_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  check ((status = 'closing') = (closing_at is not null))
);

create table public.platform_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- One profile per user, so a user belongs to exactly one office
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  org_id uuid not null references public.organizations (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 200),
  phone_e164 text check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  role text not null default 'staff' check (role in ('admin', 'staff')),
  is_active boolean not null default true,
  -- Bumped on role/active changes and handovers; clients wipe and re-pull when it moves (§10.3)
  permission_version integer not null default 1,
  quiet_start time,
  quiet_end time,
  notification_prefs jsonb not null default '{}'::jsonb
    check (jsonb_typeof(notification_prefs) = 'object'),
  terms_accepted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  unique (org_id, id),
  check ((quiet_start is null) = (quiet_end is null))
);
create index profiles_org_id_idx on public.profiles (org_id);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  email text not null
    check (email = lower(btrim(email)) and email like '%_@_%' and char_length(email) <= 320),
  role text not null default 'staff' check (role in ('admin', 'staff')),
  invited_by uuid not null,
  expires_at timestamptz not null default now() + interval '7 days',
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (org_id, id),
  foreign key (org_id, invited_by) references public.profiles (org_id, id) on delete cascade
);
-- FR-AUTH-03: at most one open invite per address and office
create unique index invitations_open_email_idx on public.invitations (org_id, email)
  where used_at is null and revoked_at is null;

-- Rule 2: the secret lives in its own table that no client role can read
create table public.invitation_tokens (
  invitation_id uuid primary key,
  org_id uuid not null,
  token_hash text not null unique,
  foreign key (org_id, invitation_id) references public.invitations (org_id, id) on delete cascade
);

create table public.org_usage (
  org_id uuid primary key references public.organizations (id) on delete cascade,
  property_count integer not null default 0 check (property_count >= 0),
  request_count integer not null default 0 check (request_count >= 0),
  user_count integer not null default 0 check (user_count >= 0),
  media_bytes bigint not null default 0 check (media_bytes >= 0),
  forms_month date,
  forms_this_month integer not null default 0 check (forms_this_month >= 0),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- RLS helpers (§8.3): security definer so policies can read profiles without recursion
-- ---------------------------------------------------------------------------------------------

-- Null for inactive users, which empties every org-scoped policy (FR-AUTH-04)
create function app.current_org_id() returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.org_id from public.profiles p where p.id = auth.uid() and p.is_active
$$;

create function app.is_admin() returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active and p.role = 'admin'
  )
$$;

create function app.is_platform_admin() returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.platform_admins a where a.user_id = auth.uid())
$$;

-- Suspended or closing offices stay readable but reject writes
create function app.org_is_writable() returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.organizations o on o.id = p.org_id
    where p.id = auth.uid() and p.is_active and o.status = 'active'
  )
$$;

grant execute on function
  app.current_org_id(), app.is_admin(), app.is_platform_admin(), app.org_is_writable()
  to authenticated, service_role;

-- Colleagues' names for "responsible: …" labels; no phone or settings leave the profile row
create function public.list_org_members()
returns table (id uuid, name text, role text, is_active boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name, p.role, p.is_active
  from public.profiles p
  where p.org_id = app.current_org_id()
  order by app.tr_lower(p.name), p.id
$$;
revoke all on function public.list_org_members() from public, anon;
grant execute on function public.list_org_members() to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Op-id de-duplication (ADR-0001 rule 3)
-- Clients send each outbox write with an `x-op-id` header. touch_row claims (op, table, row)
-- once; a retry whose first attempt already landed is skipped, so it can neither bump the
-- version again nor overwrite a newer write from another device.
-- ---------------------------------------------------------------------------------------------

create table app.applied_ops (
  op_id uuid not null,
  table_name text not null,
  row_id uuid not null,
  org_id uuid,
  user_id uuid,
  applied_at timestamptz not null default now(),
  primary key (op_id, table_name, row_id)
);
-- The nightly cleanup (step 10) drops claims older than the outbox can retry
create index applied_ops_applied_at_idx on app.applied_ops (applied_at);
alter table app.applied_ops enable row level security;
revoke all on app.applied_ops from public, anon, authenticated;

create function app.claim_op(p_op_id uuid, p_table text, p_row_id uuid) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into app.applied_ops (op_id, table_name, row_id, org_id, user_id)
  values (p_op_id, p_table, p_row_id, app.current_org_id(), auth.uid())
  on conflict do nothing;
  return found;
end;
$$;
revoke all on function app.claim_op(uuid, text, uuid) from public, anon;
grant execute on function app.claim_op(uuid, text, uuid) to authenticated, service_role;

create or replace function app.touch_row() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  op_id uuid := nullif(current_setting('request.headers', true), '')::json ->> 'x-op-id';
begin
  if op_id is not null
    and not app.claim_op(op_id, tg_table_schema || '.' || tg_table_name, new.id) then
    return null;
  end if;

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

-- ---------------------------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------------------------

create trigger touch before insert or update on public.organizations
  for each row execute function app.touch_row();
create trigger touch before insert or update on public.profiles
  for each row execute function app.touch_row();

create function app.bump_permission_version() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.role is distinct from old.role or new.is_active is distinct from old.is_active then
    new.permission_version := old.permission_version + 1;
  end if;
  return new;
end;
$$;
create trigger bump_permission_version before update on public.profiles
  for each row execute function app.bump_permission_version();

-- Every office gets its usage row; counters are maintained server-side
create function app.create_org_usage() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.org_usage (org_id) values (new.id);
  return null;
end;
$$;
create trigger create_usage after insert on public.organizations
  for each row execute function app.create_org_usage();

-- ---------------------------------------------------------------------------------------------
-- Privileges and policies. Supabase grants new public tables to anon/authenticated by default,
-- so everything is revoked first and only what a policy needs is granted back.
-- ---------------------------------------------------------------------------------------------

revoke all on
  public.plans, public.organizations, public.platform_admins, public.profiles,
  public.invitations, public.invitation_tokens, public.org_usage
  from anon, authenticated;

alter table public.plans enable row level security;
alter table public.organizations enable row level security;
alter table public.platform_admins enable row level security;
alter table public.profiles enable row level security;
alter table public.invitations enable row level security;
alter table public.invitation_tokens enable row level security;
alter table public.org_usage enable row level security;

-- plans: reference data
grant select on public.plans to authenticated;
create policy plans_select on public.plans
  for select to authenticated using (true);

-- organizations: members read; admins edit branding and settings, never plan or status
grant select on public.organizations to authenticated;
grant update (
  name, legal_name, license_no, logo_path, brand_color, contact, signature_text, settings
) on public.organizations to authenticated;
create policy organizations_select on public.organizations
  for select to authenticated
  using (id = (select app.current_org_id()) or (select app.is_platform_admin()));
create policy organizations_update_admin on public.organizations
  for update to authenticated
  using (
    id = (select app.current_org_id())
    and (select app.is_admin())
    and (select app.org_is_writable())
  )
  with check (id = (select app.current_org_id()));

-- platform_admins: only your own row
grant select on public.platform_admins to authenticated;
create policy platform_admins_select_self on public.platform_admins
  for select to authenticated using (user_id = (select auth.uid()));

-- profiles: your own row, or every row of your office if admin; role and status are not
-- client-writable (admin functions in M2)
grant select on public.profiles to authenticated;
grant update (name, phone_e164, quiet_start, quiet_end, notification_prefs)
  on public.profiles to authenticated;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (id = (select auth.uid()) or (select app.is_admin()))
  );
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (
    id = (select auth.uid())
    and org_id = (select app.current_org_id())
    and (select app.org_is_writable())
  )
  with check (id = (select auth.uid()) and org_id = (select app.current_org_id()));

-- invitations: admins read; created and revoked through M2 functions
grant select on public.invitations to authenticated;
create policy invitations_select_admin on public.invitations
  for select to authenticated
  using (org_id = (select app.current_org_id()) and (select app.is_admin()));

-- invitation_tokens: RLS on, no policies, no grants: server only

-- org_usage: admins read their counters
grant select on public.org_usage to authenticated;
create policy org_usage_select_admin on public.org_usage
  for select to authenticated
  using (org_id = (select app.current_org_id()) and (select app.is_admin()));
