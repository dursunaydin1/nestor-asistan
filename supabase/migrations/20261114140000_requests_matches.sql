-- M1 step 6: requests, interests and matches (FR-REQ-01..03, FR-MATCH-01..08, matching.md §9).
-- A request belongs to its person's owner (rule 3). Matches are created only by the server
-- (match Edge Function, M5); the property's agent never sees a colleague's match, only the
-- "your property has a match" notification without client details (FR-MATCH-08).
-- request_regions depends on the region tables and comes with step 3.

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  person_id uuid not null,
  owner_id uuid not null,
  kind text not null check (kind in ('residential', 'commercial', 'land', 'agricultural')),
  transactions text[] not null
    check (
      cardinality(transactions) between 1 and 5
      and transactions <@ array['sale', 'rent', 'transfer_sale', 'transfer_rent', 'swap']::text[]
    ),
  budget_min numeric(14, 2) check (budget_min >= 0),
  budget_max numeric(14, 2) check (budget_max > 0),
  area_min numeric(10, 2) check (area_min > 0),
  area_max numeric(10, 2) check (area_max > 0),
  rooms text[] check (cardinality(rooms) <= 20),
  urgency text not null default 'normal' check (urgency in ('low', 'normal', 'high')),
  payment text[] check (payment <@ array['cash', 'loan', 'swap']::text[]),
  -- Extras (lift, parking…) and land preferences (zoning, share, road/water/power)
  preferences jsonb not null default '{}'::jsonb check (jsonb_typeof(preferences) = 'object'),
  notes text check (char_length(notes) <= 4000),
  -- FR-REQ-02
  status text not null default 'active' check (status in ('active', 'paused', 'closed')),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  unique (org_id, id),
  -- Lets request_interests prove its request belongs to the same person
  unique (id, person_id),
  foreign key (org_id, person_id) references public.persons (org_id, id) on delete cascade,
  check (budget_min is null or budget_max is null or budget_min <= budget_max),
  check (area_min is null or area_max is null or area_min <= area_max)
);
create index requests_org_owner_idx on public.requests (org_id, owner_id);
create index requests_org_person_idx on public.requests (org_id, person_id);
create index requests_org_updated_idx on public.requests (org_id, updated_at, id);
create index requests_org_active_idx on public.requests (org_id, kind)
  where status = 'active' and deleted_at is null;

-- FR-REQ-03: properties a person asked about
create table public.request_interests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  person_id uuid not null,
  owner_id uuid not null,
  request_id uuid,
  property_id uuid not null,
  source text not null default 'other'
    check (source in ('call', 'walk_in', 'listing', 'public_form', 'other')),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  foreign key (org_id, person_id) references public.persons (org_id, id) on delete cascade,
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade,
  foreign key (request_id, person_id) references public.requests (id, person_id) on delete cascade
);
create unique index request_interests_unique_idx on public.request_interests (person_id, property_id)
  where deleted_at is null;
-- property_interest_count (step 9)
create index request_interests_property_idx on public.request_interests (org_id, property_id)
  where deleted_at is null;
create index request_interests_owner_idx on public.request_interests (org_id, owner_id);

-- status is the user's workflow (FR-MATCH-07); invalid_at marks a pair that no longer meets the
-- hard criteria. Keeping them apart preserves "called"/"shown" when a match turns invalid (§9.4).
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  request_id uuid not null,
  owner_id uuid not null,
  -- external_listing_id joins in phase 2 (FR-MATCH-09)
  property_id uuid not null,
  score smallint not null check (score between 0 and 100),
  tags text[] not null default '{}',
  score_detail jsonb not null default '{}'::jsonb check (jsonb_typeof(score_detail) = 'object'),
  status text not null default 'suggested'
    check (status in ('suggested', 'called', 'shown', 'not_interested', 'offered', 'closed')),
  invalid_at timestamptz,
  notified_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  unique (org_id, id),
  unique (request_id, property_id),
  foreign key (org_id, request_id) references public.requests (org_id, id) on delete cascade,
  foreign key (org_id, property_id) references public.properties (org_id, id) on delete cascade
);
create index matches_org_owner_idx on public.matches (org_id, owner_id);
create index matches_org_property_idx on public.matches (org_id, property_id);
create index matches_org_updated_idx on public.matches (org_id, updated_at, id);

create table public.match_status_history (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  match_id uuid not null,
  owner_id uuid not null,
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now(),
  foreign key (org_id, match_id) references public.matches (org_id, id) on delete cascade
);
create index match_status_history_match_idx on public.match_status_history (org_id, match_id, changed_at);
create index match_status_history_owner_idx on public.match_status_history (org_id, owner_id);

-- Work queue for the match function (§9.5); server only
create table public.match_jobs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  target_type text not null check (target_type in ('property', 'request', 'org')),
  target_id uuid not null,
  reason text check (char_length(reason) <= 200),
  status text not null default 'pending' check (status in ('pending', 'running', 'done', 'failed')),
  attempts smallint not null default 0 check (attempts >= 0),
  error text check (char_length(error) <= 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- One pending job per target (de-duplication)
create unique index match_jobs_pending_idx on public.match_jobs (target_type, target_id)
  where status = 'pending';
create index match_jobs_status_idx on public.match_jobs (status, created_at);

-- ---------------------------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------------------------

create trigger copy_owner before insert or update on public.requests
  for each row execute function app.copy_parent_owner('public.persons', 'person_id');
create trigger touch before insert or update on public.requests
  for each row execute function app.touch_row();

create trigger copy_owner before insert or update on public.request_interests
  for each row execute function app.copy_parent_owner('public.persons', 'person_id');
create trigger touch before insert or update on public.request_interests
  for each row execute function app.touch_row();

create trigger copy_owner before insert or update on public.matches
  for each row execute function app.copy_parent_owner('public.requests', 'request_id');
create trigger touch before insert or update on public.matches
  for each row execute function app.touch_row();

create function app.log_match_status() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.match_status_history
      (org_id, match_id, owner_id, old_status, new_status, changed_by)
    values (
      new.org_id, new.id, new.owner_id,
      case when tg_op = 'UPDATE' then old.status end,
      new.status, auth.uid()
    );
  end if;
  return null;
end;
$$;
create trigger log_status after insert or update of status on public.matches
  for each row execute function app.log_match_status();

-- ---------------------------------------------------------------------------------------------
-- Privileges and policies
-- ---------------------------------------------------------------------------------------------

revoke all on
  public.requests, public.request_interests, public.matches, public.match_status_history,
  public.match_jobs
  from anon, authenticated;

alter table public.requests enable row level security;
alter table public.request_interests enable row level security;
alter table public.matches enable row level security;
alter table public.match_status_history enable row level security;
alter table public.match_jobs enable row level security;

-- requests: owner of the person + admin; owner_id comes from the person, so a hidden person is
-- rejected; person_id and owner_id are never client-updatable
grant select on public.requests to authenticated;
grant insert (
  id, org_id, person_id, kind, transactions, budget_min, budget_max, area_min, area_max,
  rooms, urgency, payment, preferences, notes, status
) on public.requests to authenticated;
grant update (
  kind, transactions, budget_min, budget_max, area_min, area_max, rooms, urgency, payment,
  preferences, notes, status, deleted_at
) on public.requests to authenticated;

create policy requests_select on public.requests
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy requests_insert on public.requests
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy requests_update on public.requests
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  )
  with check (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );

-- request_interests: same visibility as the person
grant select on public.request_interests to authenticated;
grant insert (id, org_id, person_id, request_id, property_id, source)
  on public.request_interests to authenticated;
grant update (source, deleted_at) on public.request_interests to authenticated;

create policy request_interests_select on public.request_interests
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy request_interests_insert on public.request_interests
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy request_interests_update on public.request_interests
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  )
  with check (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );

-- matches: the request's owner + admin read and move the workflow status; everything else is
-- written by the server (service role)
grant select on public.matches to authenticated;
grant update (status) on public.matches to authenticated;

create policy matches_select on public.matches
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy matches_update on public.matches
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  )
  with check (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );

grant select on public.match_status_history to authenticated;
create policy match_status_history_select on public.match_status_history
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );

-- match_jobs: RLS on, no policies, no grants: server only

-- Platform-wide defaults grant EXECUTE on new functions to anon (see 20261113140100)
revoke execute on all functions in schema app from public, anon;
