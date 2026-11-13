-- RLS matrix for offices, profiles, invitations, usage and plans (M1 step 2). CI only (ADR-0003).
-- Office A: admin a1, staff a2 and a3, inactive staff a4. Office B (suspended later): admin b1.
-- f1 is a platform admin with no office. All data is synthetic and rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(48);

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

insert into public.invitations (id, org_id, email, invited_by) values
  ('1a000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000',
   'new@example.test', 'a1000000-0000-0000-0000-000000000000');
insert into public.invitation_tokens (invitation_id, org_id, token_hash) values
  ('1a000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'synthetic-hash');

-- ---------------------------------------------------------------- schema guards (rule 1)
select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity $$,
  'every public table has RLS enabled'
);
select is_empty(
  $$ select t.table_name from information_schema.tables t
     where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
       and t.table_name not in ('organizations', 'plans', 'platform_admins')
       and not exists (
         select 1 from information_schema.columns c
         where c.table_schema = 'public' and c.table_name = t.table_name and c.column_name = 'org_id'
       ) $$,
  'every office table has org_id'
);
select results_eq(
  $$ select id from public.plans order by id $$,
  $$ values ('free'), ('pro'), ('standard') $$,
  'plans are seeded'
);
select is(
  (select count(*) from public.org_usage)::int,
  2,
  'every office gets a usage row'
);

-- ---------------------------------------------------------------- staff a2
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select id from public.organizations $$,
  $$ values ('0a000000-0000-0000-0000-000000000000'::uuid) $$,
  'staff sees only their own office'
);
select results_eq(
  $$ select id from public.profiles $$,
  $$ values ('a2000000-0000-0000-0000-000000000000'::uuid) $$,
  'staff sees only their own profile'
);
select results_eq(
  $$ select name from public.list_org_members() $$,
  $$ values ('Admin A'), ('Former A'), ('Staff A'), ('Staff A2') $$,
  'staff lists colleague names of their own office only'
);
select is((select count(*) from public.invitations)::int, 0, 'staff sees no invitations');
select is((select count(*) from public.org_usage)::int, 0, 'staff sees no usage counters');
select is((select count(*) from public.platform_admins)::int, 0, 'staff is not a platform admin');
select is((select count(*) from public.plans)::int, 3, 'staff can read plans');

update public.profiles set name = 'Staff A Renamed' where id = 'a2000000-0000-0000-0000-000000000000';
select is(
  (select name from public.profiles where id = 'a2000000-0000-0000-0000-000000000000'),
  'Staff A Renamed',
  'staff can edit their own name'
);
select throws_ok(
  $$ update public.profiles set role = 'admin' where id = 'a2000000-0000-0000-0000-000000000000' $$,
  '42501', null, 'staff cannot promote themselves'
);
select throws_ok(
  $$ update public.profiles set is_active = false where id = 'a2000000-0000-0000-0000-000000000000' $$,
  '42501', null, 'staff cannot change active status'
);
select throws_ok(
  $$ update public.profiles set org_id = '0b000000-0000-0000-0000-000000000000'
     where id = 'a2000000-0000-0000-0000-000000000000' $$,
  '42501', null, 'staff cannot move to another office'
);
-- Silently filtered by RLS; verified as the admin below
update public.profiles set name = 'Hijacked' where id = 'a3000000-0000-0000-0000-000000000000';
update public.organizations set name = 'Hijacked' where id = '0a000000-0000-0000-0000-000000000000';
select throws_ok(
  $$ update public.organizations set plan_id = 'pro' $$,
  '42501', null, 'staff cannot change the plan'
);
select throws_ok(
  $$ insert into public.profiles (id, org_id, name)
     values ('a2000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'x') $$,
  '42501', null, 'clients cannot create profiles'
);

-- Op-id de-duplication on a real table: profile a2 is at version 2 here
select set_config('request.headers', '{"x-op-id":"0c000000-0000-0000-0000-000000000001"}', true);
update public.profiles set name = 'Op One' where id = 'a2000000-0000-0000-0000-000000000000';
update public.profiles set name = 'Op One Retry' where id = 'a2000000-0000-0000-0000-000000000000';
select results_eq(
  $$ select name, version from public.profiles where id = 'a2000000-0000-0000-0000-000000000000' $$,
  $$ values ('Op One', 3) $$,
  'a retried op is applied once'
);
select set_config('request.headers', '{"x-op-id":"0c000000-0000-0000-0000-000000000002"}', true);
update public.profiles set name = 'Op Two' where id = 'a2000000-0000-0000-0000-000000000000';
select results_eq(
  $$ select name, version from public.profiles where id = 'a2000000-0000-0000-0000-000000000000' $$,
  $$ values ('Op Two', 4) $$,
  'a new op is applied'
);
select set_config('request.headers', '', true);
select throws_ok(
  $$ select * from app.applied_ops $$,
  '42501', null, 'clients cannot read op claims'
);

-- ---------------------------------------------------------------- admin a1
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is((select count(*) from public.profiles)::int, 4, 'admin sees every profile of the office, inactive included');
select is(
  (select name from public.profiles where id = 'a3000000-0000-0000-0000-000000000000'),
  'Staff A2',
  'staff could not rename a colleague'
);
select is(
  (select name from public.organizations where id = '0a000000-0000-0000-0000-000000000000'),
  'Office A',
  'staff could not rename the office'
);
update public.organizations set name = 'Office A Updated' where id = '0a000000-0000-0000-0000-000000000000';
select is(
  (select name from public.organizations where id = '0a000000-0000-0000-0000-000000000000'),
  'Office A Updated',
  'admin can rename the office'
);
select throws_ok(
  $$ update public.organizations set status = 'active' $$,
  '42501', null, 'admin cannot change office status'
);
select throws_ok(
  $$ update public.profiles set role = 'admin' where id = 'a3000000-0000-0000-0000-000000000000' $$,
  '42501', null, 'admin cannot change roles directly (M2 functions do)'
);
select is((select count(*) from public.invitations)::int, 1, 'admin sees office invitations');
select throws_ok(
  $$ select token_hash from public.invitation_tokens $$,
  '42501', null, 'not even an admin can read invitation tokens'
);
select is((select count(*) from public.org_usage)::int, 1, 'admin sees own usage counters');
select is(
  (select count(*) from public.organizations where id = '0b000000-0000-0000-0000-000000000000')::int,
  0,
  'admin cannot see another office'
);
select ok(app.is_admin(), 'is_admin is true for an active admin');

-- ---------------------------------------------------------------- inactive a4 (FR-AUTH-04)
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is(app.current_org_id(), null::uuid, 'inactive user has no current office');
select is((select count(*) from public.organizations)::int, 0, 'inactive user sees no office');
select is((select count(*) from public.profiles)::int, 0, 'inactive user sees no profile');
select is((select count(*) from public.list_org_members())::int, 0, 'inactive user lists no members');

-- ---------------------------------------------------------------- admin b1, office B suspended
reset role;
update public.organizations set status = 'suspended' where id = '0b000000-0000-0000-0000-000000000000';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select id from public.profiles $$,
  $$ values ('b1000000-0000-0000-0000-000000000000'::uuid) $$,
  'office B admin sees no office A profiles'
);
select is((select count(*) from public.list_org_members())::int, 1, 'office B lists only its own members');
update public.organizations set name = 'Office B Renamed' where id = '0b000000-0000-0000-0000-000000000000';
select is(
  (select name from public.organizations where id = '0b000000-0000-0000-0000-000000000000'),
  'Office B',
  'a suspended office is read-only'
);

-- ---------------------------------------------------------------- platform admin f1
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is((select count(*) from public.organizations)::int, 2, 'platform admin sees every office');
select is((select count(*) from public.platform_admins)::int, 1, 'platform admin sees own row');
select is((select count(*) from public.profiles)::int, 0, 'platform admin sees no office data');

-- ---------------------------------------------------------------- anon
reset role;
set local role anon;

select throws_ok($$ select * from public.plans $$, '42501', null, 'anon cannot read plans');
select throws_ok($$ select * from public.organizations $$, '42501', null, 'anon cannot read offices');
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon cannot read profiles');
select throws_ok($$ select * from public.invitations $$, '42501', null, 'anon cannot read invitations');
select throws_ok($$ select * from public.org_usage $$, '42501', null, 'anon cannot read usage');
select throws_ok($$ select * from public.list_org_members() $$, '42501', null, 'anon cannot list members');

-- ---------------------------------------------------------------- permission_version
reset role;
update public.profiles set role = 'admin' where id = 'a3000000-0000-0000-0000-000000000000';
select is(
  (select permission_version from public.profiles where id = 'a3000000-0000-0000-0000-000000000000'),
  2,
  'a role change bumps permission_version'
);

select * from finish();
rollback;
