-- M1 step 4: persons and their child records (FR-PER-01..06, data-model §8.2–8.3).
-- Rule 3: a staff member never sees another staff member's persons or anything hanging off them.
-- Owner changes only through the handover function (FR-ADM-06, M9) so children stay consistent.

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

create table public.persons (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id()
    references public.organizations (id) on delete cascade,
  owner_id uuid not null default auth.uid(),
  name text not null check (char_length(btrim(name)) between 1 and 200),
  phone1_e164 text check (phone1_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  phone2_e164 text check (phone2_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  email text
    check (email = lower(btrim(email)) and email like '%_@_%' and char_length(email) <= 320),
  source text check (char_length(source) <= 100),
  notes text check (char_length(notes) <= 10000),
  -- FR-PER-01: one person can be both owner and client
  roles text[] not null default '{client}'
    check (cardinality(roles) between 1 and 2 and roles <@ array['owner', 'client']::text[]),
  -- FR-PER-03
  client_status text not null default 'new'
    check (client_status in ('new', 'searching', 'viewed', 'offer', 'closed', 'gave_up', 'inactive')),
  search_text text not null default '',
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  unique (org_id, id),
  -- No cascade: a user with persons cannot be removed before a handover
  foreign key (org_id, owner_id) references public.profiles (org_id, id)
);
create index persons_org_owner_idx on public.persons (org_id, owner_id);
create index persons_org_updated_idx on public.persons (org_id, updated_at, id);
-- FR-PER-02 duplicate check (check_phone_conflict, step 9)
create index persons_org_phone1_idx on public.persons (org_id, phone1_e164)
  where phone1_e164 is not null;
create index persons_org_phone2_idx on public.persons (org_id, phone2_e164)
  where phone2_e164 is not null;

-- Written only by a trigger; the history cannot be edited
create table public.person_status_history (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  person_id uuid not null,
  owner_id uuid not null,
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now(),
  foreign key (org_id, person_id) references public.persons (org_id, id) on delete cascade
);
create index person_status_history_person_idx
  on public.person_status_history (org_id, person_id, changed_at);
create index person_status_history_owner_idx on public.person_status_history (org_id, owner_id);

-- FR-PER-04; the author is created_by
create table public.contact_log (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  person_id uuid not null,
  owner_id uuid not null,
  contacted_at timestamptz not null default now(),
  channel text not null check (channel in ('phone', 'whatsapp', 'in_person', 'other')),
  note text check (char_length(note) <= 10000),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  foreign key (org_id, person_id) references public.persons (org_id, id) on delete cascade
);
create index contact_log_person_idx on public.contact_log (org_id, person_id, contacted_at desc);
create index contact_log_owner_idx on public.contact_log (org_id, owner_id);

-- Targets are explicit nullable foreign keys instead of a type/id pair, so the database can
-- check them; property_id and request_id are added with their tables (steps 5–6).
create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id()
    references public.organizations (id) on delete cascade,
  user_id uuid not null default auth.uid(),
  person_id uuid,
  due_date date not null,
  kind text not null default 'follow_up'
    check (kind in ('call', 'follow_up', 'recontact', 'notify', 'other')),
  note text check (char_length(note) <= 2000),
  done_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  deleted_at timestamptz,
  foreign key (org_id, user_id) references public.profiles (org_id, id) on delete cascade,
  foreign key (org_id, person_id) references public.persons (org_id, id) on delete cascade
);
-- "Today" screen: open reminders per user and day (FR-TODAY-01)
create index reminders_open_idx on public.reminders (org_id, user_id, due_date)
  where done_at is null and deleted_at is null;
create index reminders_person_idx on public.reminders (org_id, person_id)
  where person_id is not null;

-- ---------------------------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------------------------

create function app.persons_search_text() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.search_text := app.search_text(new.name, new.email, new.phone1_e164, new.phone2_e164, new.source);
  return new;
end;
$$;
create trigger set_search_text before insert or update on public.persons
  for each row execute function app.persons_search_text();
create trigger touch before insert or update on public.persons
  for each row execute function app.touch_row();

-- FR-PER-03: every status, including the first, lands in the history
create function app.log_person_status() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.client_status is distinct from old.client_status then
    insert into public.person_status_history
      (org_id, person_id, owner_id, old_status, new_status, changed_by)
    values (
      new.org_id, new.id, new.owner_id,
      case when tg_op = 'UPDATE' then old.client_status end,
      new.client_status, auth.uid()
    );
  end if;
  return null;
end;
$$;
create trigger log_status after insert or update of client_status on public.persons
  for each row execute function app.log_person_status();

create trigger copy_owner before insert or update on public.contact_log
  for each row execute function app.copy_parent_owner('public.persons', 'person_id');
create trigger touch before insert or update on public.contact_log
  for each row execute function app.touch_row();

create trigger touch before insert or update on public.reminders
  for each row execute function app.touch_row();

-- ---------------------------------------------------------------------------------------------
-- Privileges and policies
-- ---------------------------------------------------------------------------------------------

revoke all on public.persons, public.person_status_history, public.contact_log, public.reminders
  from anon, authenticated;

alter table public.persons enable row level security;
alter table public.person_status_history enable row level security;
alter table public.contact_log enable row level security;
alter table public.reminders enable row level security;

-- persons: owner + admin. owner_id, org_id and search_text are never client-updatable.
grant select on public.persons to authenticated;
grant insert (
  id, org_id, owner_id, name, phone1_e164, phone2_e164, email, source, notes, roles, client_status
) on public.persons to authenticated;
grant update (
  name, phone1_e164, phone2_e164, email, source, notes, roles, client_status, deleted_at
) on public.persons to authenticated;

create policy persons_select on public.persons
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy persons_insert on public.persons
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy persons_update on public.persons
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

-- person_status_history: read-only, same visibility as the person
grant select on public.person_status_history to authenticated;
create policy person_status_history_select on public.person_status_history
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );

-- contact_log: owner_id comes from the person (copy_owner), so a hidden person is rejected
grant select on public.contact_log to authenticated;
grant insert (id, org_id, person_id, contacted_at, channel, note)
  on public.contact_log to authenticated;
grant update (contacted_at, channel, note, deleted_at) on public.contact_log to authenticated;

create policy contact_log_select on public.contact_log
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy contact_log_insert on public.contact_log
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (owner_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy contact_log_update on public.contact_log
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

-- reminders: assignee + admin. A reminder about a person may only go to someone who can see
-- that person (its owner or an admin), so it cannot leak a colleague's client (rule 3).
grant select on public.reminders to authenticated;
grant insert (id, org_id, user_id, person_id, due_date, kind, note, done_at)
  on public.reminders to authenticated;
grant update (user_id, due_date, kind, note, done_at, deleted_at)
  on public.reminders to authenticated;

create policy reminders_select on public.reminders
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (user_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy reminders_insert on public.reminders
  for insert to authenticated
  with check (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (user_id = (select auth.uid()) or (select app.is_admin()))
    and (
      reminders.person_id is null
      or exists (
        select 1 from public.persons p
        where p.id = reminders.person_id
          and (
            p.owner_id = reminders.user_id
            or exists (
              select 1 from public.profiles pr
              where pr.id = reminders.user_id and pr.role = 'admin' and pr.is_active
            )
          )
      )
    )
  );
create policy reminders_update on public.reminders
  for update to authenticated
  using (
    org_id = (select app.current_org_id())
    and (select app.org_is_writable())
    and (user_id = (select auth.uid()) or (select app.is_admin()))
  )
  with check (
    org_id = (select app.current_org_id())
    and (user_id = (select auth.uid()) or (select app.is_admin()))
    and (
      reminders.person_id is null
      or exists (
        select 1 from public.persons p
        where p.id = reminders.person_id
          and (
            p.owner_id = reminders.user_id
            or exists (
              select 1 from public.profiles pr
              where pr.id = reminders.user_id and pr.role = 'admin' and pr.is_active
            )
          )
      )
    )
  );

-- Platform-wide defaults grant EXECUTE on new functions to anon (see 20261113140100)
revoke execute on all functions in schema app from public, anon;
