-- M1 step 5: properties and their private/child tables (FR-PROP-01..13, PRD §6, data-model §8.2–8.3).
-- The portfolio is shared inside the office; only the agent and admins edit a property or see its
-- secrets (rule 2: secrets live in separate tables). Region columns arrive with step 3.

-- ---------------------------------------------------------------------------------------------
-- Per-office counters (short property codes)
-- ---------------------------------------------------------------------------------------------

create table app.org_counters (
  org_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  value bigint not null default 0,
  primary key (org_id, name)
);
alter table app.org_counters enable row level security;
revoke all on app.org_counters from public, anon, authenticated;

create function app.next_counter(p_org_id uuid, p_name text) returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into app.org_counters as c (org_id, name, value) values (p_org_id, p_name, 1)
  on conflict (org_id, name) do update set value = c.value + 1
  returning c.value
$$;
grant execute on function app.next_counter(uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id()
    references public.organizations (id) on delete cascade,
  agent_id uuid not null default auth.uid(),
  -- Short office-wide number shown as "#12"; never used in public URLs (qr_links has its own code)
  code integer not null,
  -- FR-PROP-01
  kind text not null check (kind in ('residential', 'commercial', 'land', 'agricultural')),
  -- FR-PROP-02 / D-04: several transactions, each with its own price
  transactions text[] not null
    check (
      cardinality(transactions) between 1 and 5
      and transactions <@ array['sale', 'rent', 'transfer_sale', 'transfer_rent', 'swap']::text[]
    ),
  price_sale numeric(14, 2) check (price_sale > 0),
  price_rent numeric(14, 2) check (price_rent > 0),
  price_transfer numeric(14, 2) check (price_transfer > 0),
  -- FR-PROP-12
  status text not null default 'active'
    check (status in ('active', 'optioned', 'sold', 'rented', 'archived', 'inactive')),
  title text check (char_length(title) <= 200),
  description text check (char_length(description) <= 10000),
  address text check (char_length(address) <= 500),
  lat numeric(9, 6) check (lat between -90 and 90),
  lng numeric(9, 6) check (lng between -180 and 180),
  rooms text check (rooms ~ '^[0-9]{1,2}\+[0-9]{1,2}$'),
  area_gross numeric(10, 2) check (area_gross > 0),
  area_net numeric(10, 2) check (area_net > 0),
  floor smallint check (floor between -10 and 200),
  -- Type-specific fields (FR-PROP-05..07); zod schema in packages/shared (step 11)
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  completeness smallint not null default 0 check (completeness between 0 and 100),
  search_text text not null default '',
  -- FR-PROP-15 staleness
  last_checked_at timestamptz not null default now(),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  unique (org_id, id),
  unique (org_id, code),
  -- No cascade: an agent with properties cannot be removed before a handover
  foreign key (org_id, agent_id) references public.profiles (org_id, id),
  -- Every priced transaction needs its price; swap stays optional (FR-PROP-02)
  check (not ('sale' = any (transactions)) or price_sale is not null),
  check (not ('rent' = any (transactions)) or price_rent is not null),
  check (
    not (transactions && array['transfer_sale', 'transfer_rent']::text[])
    or price_transfer is not null
  ),
  check ((lat is null) = (lng is null))
);
create index properties_org_agent_idx on public.properties (org_id, agent_id);
create index properties_org_updated_idx on public.properties (org_id, updated_at, id);
create index properties_org_status_idx on public.properties (org_id, status)
  where deleted_at is null;

-- 1:1 with properties; id is the property id
create table public.property_private (
  id uuid primary key,
  org_id uuid not null default app.current_org_id(),
  min_price_sale numeric(14, 2) check (min_price_sale > 0),
  min_price_rent numeric(14, 2) check (min_price_rent > 0),
  negotiation_note text check (char_length(negotiation_note) <= 4000),
  commission_buyer_rate numeric(5, 2) check (commission_buyer_rate between 0 and 100),
  commission_buyer_amount numeric(14, 2) check (commission_buyer_amount >= 0),
  commission_seller_rate numeric(5, 2) check (commission_seller_rate between 0 and 100),
  commission_seller_amount numeric(14, 2) check (commission_seller_amount >= 0),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  foreign key (org_id, id) references public.properties (org_id, id) on delete cascade
);

create table public.property_private_history (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  property_id uuid not null,
  field text not null,
  old_value text,
  new_value text,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now(),
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade
);
create index property_private_history_property_idx
  on public.property_private_history (org_id, property_id, changed_at);

-- FR-PROP-08: several owners, one contact person
create table public.property_owners (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  property_id uuid not null,
  person_id uuid not null,
  share_ratio numeric(5, 2) check (share_ratio > 0 and share_ratio <= 100),
  is_contact boolean not null default false,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade,
  foreign key (org_id, person_id) references public.persons (org_id, id) on delete cascade
);
create unique index property_owners_unique_idx on public.property_owners (property_id, person_id)
  where deleted_at is null;
create unique index property_owners_contact_idx on public.property_owners (property_id)
  where is_contact and deleted_at is null;
create index property_owners_person_idx on public.property_owners (org_id, person_id);

-- Rows only; files and their policies come with the storage buckets (step 9)
create table public.property_media (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  property_id uuid not null,
  kind text not null check (kind in ('photo', 'video', 'doc')),
  storage_path text not null check (char_length(storage_path) <= 500),
  sort_order smallint not null default 0,
  size_bytes bigint check (size_bytes >= 0),
  -- Server-made copy in the public-media bucket (FR-PUB, M10)
  public_copy_path text check (char_length(public_copy_path) <= 500),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade
);
create index property_media_property_idx on public.property_media (org_id, property_id, sort_order);

-- FR-PROP-09: listing prices per transaction
create table public.property_price_history (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  property_id uuid not null,
  price_kind text not null check (price_kind in ('sale', 'rent', 'transfer')),
  old_price numeric(14, 2),
  new_price numeric(14, 2),
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now(),
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade
);
create index property_price_history_property_idx
  on public.property_price_history (org_id, property_id, changed_at);

create table public.property_status_history (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  property_id uuid not null,
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now(),
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade
);
create index property_status_history_property_idx
  on public.property_status_history (org_id, property_id, changed_at);

-- FR-PROP-13: colleagues leave a note instead of editing
create table public.property_change_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  property_id uuid not null,
  requested_by uuid not null default auth.uid(),
  note text not null check (char_length(btrim(note)) between 1 and 2000),
  status text not null default 'open' check (status in ('open', 'done', 'dismissed')),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade,
  foreign key (org_id, requested_by) references public.profiles (org_id, id) on delete cascade
);
create index property_change_requests_open_idx on public.property_change_requests (org_id, property_id)
  where status = 'open';

-- Reminders can now point at a property (data-model: explicit target FKs)
alter table public.reminders add column property_id uuid;
alter table public.reminders
  add foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade;
create index reminders_property_idx on public.reminders (org_id, property_id)
  where property_id is not null;

-- ---------------------------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------------------------

-- Agent or admin of the property's office (data-model §8.3)
create function app.can_edit_property(p_property_id uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.properties p
    where p.id = p_property_id
      and p.org_id = app.current_org_id()
      and (p.agent_id = auth.uid() or app.is_admin())
  )
$$;
grant execute on function app.can_edit_property(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------------------------

create function app.assign_property_code() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.code := app.next_counter(new.org_id, 'property');
  else
    new.code := old.code;
  end if;
  return new;
end;
$$;
-- Trigger names fire alphabetically: assign_code, set_search_text, touch
create trigger assign_code before insert or update on public.properties
  for each row execute function app.assign_property_code();

create function app.properties_search_text() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.search_text := app.search_text(new.code::text, new.title, new.address);
  return new;
end;
$$;
create trigger set_search_text before insert or update on public.properties
  for each row execute function app.properties_search_text();
create trigger touch before insert or update on public.properties
  for each row execute function app.touch_row();

create function app.log_property_price() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.price_sale is distinct from (case when tg_op = 'UPDATE' then old.price_sale end) then
    insert into public.property_price_history (org_id, property_id, price_kind, old_price, new_price, changed_by)
    values (new.org_id, new.id, 'sale', case when tg_op = 'UPDATE' then old.price_sale end, new.price_sale, auth.uid());
  end if;
  if new.price_rent is distinct from (case when tg_op = 'UPDATE' then old.price_rent end) then
    insert into public.property_price_history (org_id, property_id, price_kind, old_price, new_price, changed_by)
    values (new.org_id, new.id, 'rent', case when tg_op = 'UPDATE' then old.price_rent end, new.price_rent, auth.uid());
  end if;
  if new.price_transfer is distinct from (case when tg_op = 'UPDATE' then old.price_transfer end) then
    insert into public.property_price_history (org_id, property_id, price_kind, old_price, new_price, changed_by)
    values (new.org_id, new.id, 'transfer', case when tg_op = 'UPDATE' then old.price_transfer end, new.price_transfer, auth.uid());
  end if;
  return null;
end;
$$;
create trigger log_price after insert or update of price_sale, price_rent, price_transfer
  on public.properties
  for each row execute function app.log_property_price();

create function app.log_property_status() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.property_status_history (org_id, property_id, old_status, new_status, changed_by)
    values (new.org_id, new.id, case when tg_op = 'UPDATE' then old.status end, new.status, auth.uid());
  end if;
  return null;
end;
$$;
create trigger log_status after insert or update of status on public.properties
  for each row execute function app.log_property_status();

create trigger touch before insert or update on public.property_private
  for each row execute function app.touch_row();

-- One history row per changed private field
create function app.log_property_private() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_row jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  new_row jsonb := to_jsonb(new);
  field text;
begin
  foreach field in array array[
    'min_price_sale', 'min_price_rent', 'negotiation_note',
    'commission_buyer_rate', 'commission_buyer_amount',
    'commission_seller_rate', 'commission_seller_amount'
  ] loop
    if (old_row ->> field) is distinct from (new_row ->> field) then
      insert into public.property_private_history
        (org_id, property_id, field, old_value, new_value, changed_by)
      values (new.org_id, new.id, field, old_row ->> field, new_row ->> field, auth.uid());
    end if;
  end loop;
  return null;
end;
$$;
create trigger log_private after insert or update on public.property_private
  for each row execute function app.log_property_private();

create trigger touch before insert or update on public.property_owners
  for each row execute function app.touch_row();
create trigger touch before insert or update on public.property_media
  for each row execute function app.touch_row();
create trigger touch before insert or update on public.property_change_requests
  for each row execute function app.touch_row();

-- ---------------------------------------------------------------------------------------------
-- Privileges and policies
-- ---------------------------------------------------------------------------------------------

revoke all on
  public.properties, public.property_private, public.property_private_history,
  public.property_owners, public.property_media, public.property_price_history,
  public.property_status_history, public.property_change_requests
  from anon, authenticated;

alter table public.properties enable row level security;
alter table public.property_private enable row level security;
alter table public.property_private_history enable row level security;
alter table public.property_owners enable row level security;
alter table public.property_media enable row level security;
alter table public.property_price_history enable row level security;
alter table public.property_status_history enable row level security;
alter table public.property_change_requests enable row level security;

-- properties: office-wide read; agent + admin write. agent_id, code, org_id, search_text are
-- never client-updatable (agent changes via handover, FR-ADM-06).
grant select on public.properties to authenticated;
grant insert (
  id, org_id, agent_id, kind, transactions, price_sale, price_rent, price_transfer, status,
  title, description, address, lat, lng, rooms, area_gross, area_net, floor, details, completeness
) on public.properties to authenticated;
grant update (
  kind, transactions, price_sale, price_rent, price_transfer, status, title, description,
  address, lat, lng, rooms, area_gross, area_net, floor, details, completeness,
  last_checked_at, deleted_at
) on public.properties to authenticated;

create policy properties_select on public.properties
  for select to authenticated
  using (org_id = (select app.current_org_id()));
create policy properties_insert on public.properties
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (agent_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy properties_update on public.properties
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (agent_id = (select auth.uid()) or (select app.is_admin()))
  )
  with check (
    org_id = (select app.current_org_id())
    and (agent_id = (select auth.uid()) or (select app.is_admin()))
  );

-- property_private: agent + admin only (PRD §6)
grant select on public.property_private to authenticated;
grant insert (
  id, org_id, min_price_sale, min_price_rent, negotiation_note,
  commission_buyer_rate, commission_buyer_amount, commission_seller_rate, commission_seller_amount
) on public.property_private to authenticated;
grant update (
  min_price_sale, min_price_rent, negotiation_note,
  commission_buyer_rate, commission_buyer_amount, commission_seller_rate, commission_seller_amount
) on public.property_private to authenticated;

create policy property_private_select on public.property_private
  for select to authenticated
  using (org_id = (select app.current_org_id()) and app.can_edit_property(id));
create policy property_private_insert on public.property_private
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and app.can_edit_property(id)
  );
create policy property_private_update on public.property_private
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and app.can_edit_property(id)
  )
  with check (org_id = (select app.current_org_id()) and app.can_edit_property(id));

grant select on public.property_private_history to authenticated;
create policy property_private_history_select on public.property_private_history
  for select to authenticated
  using (org_id = (select app.current_org_id()) and app.can_edit_property(property_id));

-- property_owners: agent + admin; the linked person must be visible to the caller, so nobody
-- can attach a colleague's client and read their details through the property (rule 3)
grant select on public.property_owners to authenticated;
grant insert (id, org_id, property_id, person_id, share_ratio, is_contact)
  on public.property_owners to authenticated;
grant update (share_ratio, is_contact, deleted_at) on public.property_owners to authenticated;

create policy property_owners_select on public.property_owners
  for select to authenticated
  using (org_id = (select app.current_org_id()) and app.can_edit_property(property_id));
create policy property_owners_insert on public.property_owners
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and app.can_edit_property(property_id)
    and exists (select 1 from public.persons pe where pe.id = property_owners.person_id)
  );
create policy property_owners_update on public.property_owners
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and app.can_edit_property(property_id)
  )
  with check (org_id = (select app.current_org_id()) and app.can_edit_property(property_id));

-- property_media: photos and videos office-wide, documents agent + admin; kind is fixed
grant select on public.property_media to authenticated;
grant insert (id, org_id, property_id, kind, storage_path, sort_order, size_bytes)
  on public.property_media to authenticated;
grant update (sort_order, deleted_at) on public.property_media to authenticated;

create policy property_media_select on public.property_media
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (kind <> 'doc' or app.can_edit_property(property_id))
  );
create policy property_media_insert on public.property_media
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and app.can_edit_property(property_id)
  );
create policy property_media_update on public.property_media
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and app.can_edit_property(property_id)
  )
  with check (org_id = (select app.current_org_id()) and app.can_edit_property(property_id));

-- Listing price and status history: office-wide, written only by triggers
grant select on public.property_price_history, public.property_status_history to authenticated;
create policy property_price_history_select on public.property_price_history
  for select to authenticated using (org_id = (select app.current_org_id()));
create policy property_status_history_select on public.property_status_history
  for select to authenticated using (org_id = (select app.current_org_id()));

-- property_change_requests: any active member may ask; the agent or an admin closes
grant select on public.property_change_requests to authenticated;
grant insert (id, org_id, property_id, note) on public.property_change_requests to authenticated;
grant update (status) on public.property_change_requests to authenticated;

create policy property_change_requests_select on public.property_change_requests
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (requested_by = (select auth.uid()) or app.can_edit_property(property_id))
  );
create policy property_change_requests_insert on public.property_change_requests
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and requested_by = (select auth.uid())
  );
create policy property_change_requests_update on public.property_change_requests
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and app.can_edit_property(property_id)
  )
  with check (org_id = (select app.current_org_id()) and app.can_edit_property(property_id));

-- reminders: the new target column
grant insert (property_id) on public.reminders to authenticated;

-- Platform-wide defaults grant EXECUTE on new functions to anon (see 20261113140100)
revoke execute on all functions in schema app from public, anon;
