-- RLS matrix for notifications, push subscriptions, login history and support tickets (M1 step 7).
-- Office A: admin a1, staff a2 and a3, inactive staff a4. Office B (suspended later): admin b1.
-- f1 is a platform admin. All data is synthetic and rolled back. CI only (ADR-0003).
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000000', 'a1@example.test'),
  ('a2000000-0000-0000-0000-000000000000', 'a2@example.test'),
  ('a3000000-0000-0000-0000-000000000000', 'a3@example.test'),
  ('a4000000-0000-0000-0000-000000000000', 'a4@example.test'),
  ('b1000000-0000-0000-0000-000000000000', 'b1@example.test'),
  ('f1000000-0000-0000-0000-000000000000', 'f1@example.test');

insert into public.organizations (id, name) values
  ('0a000000-0000-0000-0000-000000000000', 'Office A'),
  ('0b000000-0000-0000-0000-000000000000', 'Office B');

insert into public.profiles (id, org_id, name, role, is_active) values
  ('a1000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Admin A', 'admin', true),
  ('a2000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Staff A', 'staff', true),
  ('a3000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Staff A2', 'staff', true),
  ('a4000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Former A', 'staff', false),
  ('b1000000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000', 'Admin B', 'admin', true);

insert into public.platform_admins (user_id) values ('f1000000-0000-0000-0000-000000000000');

insert into public.notifications (id, org_id, user_id, kind, payload) values
  ('1e200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'reminder', '{}'),
  ('1e300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'reminder', '{}'),
  ('1e400000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a4000000-0000-0000-0000-000000000000', 'reminder', '{}');
insert into public.push_subscriptions (org_id, user_id, endpoint, p256dh, auth_secret) values
  ('0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'https://push.example.test/a3', 'k', 'a');
insert into public.login_history (org_id, user_id, user_agent) values
  ('0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'test');
insert into public.support_tickets (org_id, user_id, subject, message) values
  ('0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'Soru', 'Nasıl yapılır?');

-- ---------------------------------------------------------------- staff a2
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select id from public.notifications $$,
  $$ values ('1e200000-0000-0000-0000-000000000000'::uuid) $$,
  'a user sees only their own notifications'
);
update public.notifications set read_at = now() where id = '1e200000-0000-0000-0000-000000000000';
select isnt(
  (select read_at from public.notifications where id = '1e200000-0000-0000-0000-000000000000'),
  null,
  'the recipient can mark a notification read'
);
select throws_ok(
  $$ update public.notifications set payload = '{"x":1}' $$,
  '42501', null, 'the payload cannot be edited'
);
select throws_ok(
  $$ insert into public.notifications (org_id, user_id, kind)
     values ('0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'fake') $$,
  '42501', null, 'clients cannot create notifications'
);
-- Filtered by RLS; verified as a3 below
update public.notifications set read_at = now() where id = '1e300000-0000-0000-0000-000000000000';

insert into public.push_subscriptions (endpoint, p256dh, auth_secret)
values ('https://push.example.test/a2', 'k', 'a');
select is((select count(*) from public.push_subscriptions)::int, 1, 'a user sees only their own push subscriptions');
delete from public.push_subscriptions where endpoint = 'https://push.example.test/a2';
select is((select count(*) from public.push_subscriptions)::int, 0, 'a user can unsubscribe');
select throws_ok(
  $$ insert into public.push_subscriptions (endpoint, p256dh, auth_secret) values ('http://insecure.test', 'k', 'a') $$,
  '23514', null, 'push endpoints must be https'
);

insert into public.login_history (user_agent) values ('Chrome Android');
select is(
  (select user_id from public.login_history),
  'a2000000-0000-0000-0000-000000000000'::uuid,
  'a user logs only their own sign-in and sees only their own history'
);
select throws_ok(
  $$ insert into public.login_history (user_id, user_agent) values ('a3000000-0000-0000-0000-000000000000', 'x') $$,
  '42501', null, 'a sign-in cannot be logged for someone else'
);

insert into public.support_tickets (subject, message) values ('Öneri', 'Harita eklensin');
select is((select count(*) from public.support_tickets)::int, 1, 'a user sees only their own tickets');
-- Not the platform admin: filtered by RLS, verified as f1 below
update public.support_tickets set status = 'closed';

-- ---------------------------------------------------------------- staff a3
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is(
  (select read_at from public.notifications where id = '1e300000-0000-0000-0000-000000000000'),
  null::timestamptz,
  'nobody else can mark your notifications read'
);

-- ---------------------------------------------------------------- admin a1
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.login_history)::int, 2, 'admin sees the office sign-in history');
select is((select count(*) from public.notifications)::int, 0, 'admin does not read other people''s notifications');
select is((select count(*) from public.push_subscriptions)::int, 0, 'admin does not see other people''s devices');
select is((select count(*) from public.support_tickets)::int, 0, 'admin does not read staff tickets');

-- ---------------------------------------------------------------- inactive a4
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.notifications)::int, 0, 'inactive user sees no notifications');

-- ---------------------------------------------------------------- admin b1, office B suspended
reset role;
update public.organizations set status = 'suspended' where id = '0b000000-0000-0000-0000-000000000000';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select lives_ok(
  $$ insert into public.support_tickets (subject, message) values ('Askı', 'Hesabım neden askıda?') $$,
  'a suspended office can still contact support'
);

-- ---------------------------------------------------------------- platform admin f1
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.support_tickets)::int, 3, 'platform admin sees every ticket');
select is(
  (select count(*) from public.support_tickets where status = 'open')::int,
  3,
  'staff could not close their own ticket'
);
update public.support_tickets set status = 'answered' where subject = 'Soru';
select is(
  (select status from public.support_tickets where subject = 'Soru'),
  'answered',
  'platform admin answers tickets'
);
select is((select count(*) from public.login_history)::int, 0, 'platform admin sees no office sign-ins');
select is((select count(*) from public.notifications)::int, 0, 'platform admin sees no office notifications');

-- ---------------------------------------------------------------- anon
reset role;
set local role anon;
select throws_ok($$ select * from public.notifications $$, '42501', null, 'anon cannot read notifications');
select throws_ok($$ select * from public.push_subscriptions $$, '42501', null, 'anon cannot read push subscriptions');
select throws_ok($$ select * from public.login_history $$, '42501', null, 'anon cannot read login history');
select throws_ok($$ select * from public.support_tickets $$, '42501', null, 'anon cannot read support tickets');

select * from finish();
rollback;
