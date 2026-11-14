-- M1 step 7: notifications, push subscriptions, login history, support tickets
-- (FR-NOTIF-01..03, FR-AUTH-05, FR-PLT-04, data-model §8.2). Notifications are created by the
-- server; their payload must never carry another user's client details (FR-MATCH-08, tested in M5).

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null,
  kind text not null check (char_length(kind) between 1 and 50),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  channels text[] not null default '{in_app}'
    check (cardinality(channels) >= 1 and channels <@ array['in_app', 'push', 'email']::text[]),
  -- Push/e-mail delivery time; quiet hours move it to the morning (FR-NOTIF-02)
  send_at timestamptz not null default now(),
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (org_id, user_id) references public.profiles (org_id, id) on delete cascade
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_due_idx on public.notifications (send_at) where sent_at is null;

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  user_id uuid not null default auth.uid(),
  endpoint text not null unique
    check (endpoint like 'https://%' and char_length(endpoint) <= 1000),
  p256dh text not null check (char_length(p256dh) <= 200),
  -- Web Push "auth" key; renamed so it never shadows the auth schema in policies
  auth_secret text not null check (char_length(auth_secret) <= 100),
  device text check (char_length(device) <= 200),
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (org_id, user_id) references public.profiles (org_id, id) on delete cascade
);
create index push_subscriptions_user_idx on public.push_subscriptions (user_id);

-- FR-AUTH-05 (no location)
create table public.login_history (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  user_id uuid not null default auth.uid(),
  logged_in_at timestamptz not null default now(),
  user_agent text check (char_length(user_agent) <= 500),
  device_id text check (char_length(device_id) <= 100),
  foreign key (org_id, user_id) references public.profiles (org_id, id) on delete cascade
);
create index login_history_user_idx on public.login_history (org_id, user_id, logged_in_at desc);

-- FR-PLT-04: read by the sender and the platform admin
create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default app.current_org_id(),
  user_id uuid not null default auth.uid(),
  subject text not null check (char_length(btrim(subject)) between 1 and 200),
  message text not null check (char_length(btrim(message)) between 1 and 5000),
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  foreign key (org_id, user_id) references public.profiles (org_id, id) on delete cascade
);
create index support_tickets_status_idx on public.support_tickets (status, created_at);

create trigger touch before insert or update on public.support_tickets
  for each row execute function app.touch_row();

revoke all on
  public.notifications, public.push_subscriptions, public.login_history, public.support_tickets
  from anon, authenticated;

alter table public.notifications enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.login_history enable row level security;
alter table public.support_tickets enable row level security;

-- notifications: only the recipient, who can only mark them read
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()) and org_id = (select app.current_org_id()));
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()) and org_id = (select app.current_org_id()))
  with check (user_id = (select auth.uid()) and org_id = (select app.current_org_id()));

-- push_subscriptions: own devices; unsubscribing deletes the row
grant select, delete on public.push_subscriptions to authenticated;
grant insert (id, endpoint, p256dh, auth_secret, device) on public.push_subscriptions to authenticated;
create policy push_subscriptions_select_own on public.push_subscriptions
  for select to authenticated
  using (user_id = (select auth.uid()) and org_id = (select app.current_org_id()));
create policy push_subscriptions_insert_own on public.push_subscriptions
  for insert to authenticated
  with check (user_id = (select auth.uid()) and org_id = (select app.current_org_id()));
create policy push_subscriptions_delete_own on public.push_subscriptions
  for delete to authenticated
  using (user_id = (select auth.uid()) and org_id = (select app.current_org_id()));

-- login_history: own rows + admins of the office; a client can only log its own sign-in
grant select on public.login_history to authenticated;
grant insert (id, user_agent, device_id) on public.login_history to authenticated;
create policy login_history_select on public.login_history
  for select to authenticated
  using (
    org_id = (select app.current_org_id())
    and (user_id = (select auth.uid()) or (select app.is_admin()))
  );
create policy login_history_insert_own on public.login_history
  for insert to authenticated
  with check (user_id = (select auth.uid()) and org_id = (select app.current_org_id()));

-- support_tickets: a suspended office can still write to support, so no writability check
grant select on public.support_tickets to authenticated;
grant insert (id, subject, message) on public.support_tickets to authenticated;
grant update (status) on public.support_tickets to authenticated;
create policy support_tickets_select on public.support_tickets
  for select to authenticated
  using (
    (user_id = (select auth.uid()) and org_id = (select app.current_org_id()))
    or (select app.is_platform_admin())
  );
create policy support_tickets_insert_own on public.support_tickets
  for insert to authenticated
  with check (user_id = (select auth.uid()) and org_id = (select app.current_org_id()));
create policy support_tickets_update_platform on public.support_tickets
  for update to authenticated
  using ((select app.is_platform_admin()))
  with check ((select app.is_platform_admin()));
