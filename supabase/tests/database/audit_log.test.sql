-- Change log (M1 step 8, FR-ADM-03): rows appear for critical changes, hold only changed fields,
-- and only admins of the office can read them. All data is synthetic and rolled back. CI only.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000000', 'a1@example.test'),
  ('a2000000-0000-0000-0000-000000000000', 'a2@example.test'),
  ('a3000000-0000-0000-0000-000000000000', 'a3@example.test'),
  ('b1000000-0000-0000-0000-000000000000', 'b1@example.test');

insert into public.organizations (id, name) values
  ('0a000000-0000-0000-0000-000000000000', 'Office A'),
  ('0b000000-0000-0000-0000-000000000000', 'Office B');

insert into public.profiles (id, org_id, name, role) values
  ('a1000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Admin A', 'admin'),
  ('a2000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Staff A', 'staff'),
  ('a3000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Staff A2', 'staff'),
  ('b1000000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000', 'Admin B', 'admin');

insert into public.persons (id, org_id, owner_id, name) values
  ('9a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'Ayşe Yılmaz');
insert into public.properties (id, org_id, agent_id, kind, transactions, price_sale) values
  ('7a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'residential', '{sale}', 1000000);

-- Role change by the server (M2 admin function stands in here)
update public.profiles set role = 'admin' where id = 'a3000000-0000-0000-0000-000000000000';

-- ---------------------------------------------------------------- staff a2 makes changes
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

update public.properties set price_sale = 950000 where id = '7a200000-0000-0000-0000-000000000000';
update public.persons set deleted_at = now() where id = '9a200000-0000-0000-0000-000000000000';

select is((select count(*) from public.audit_log)::int, 0, 'staff cannot read the change log');
select throws_ok(
  $$ insert into public.audit_log (org_id, action, table_name) values ('0a000000-0000-0000-0000-000000000000', 'update', 'x') $$,
  '42501', null, 'clients cannot write the change log'
);

-- ---------------------------------------------------------------- admin a1
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select before ->> 'price_sale', after ->> 'price_sale' from public.audit_log
     where table_name = 'properties' and action = 'update' $$,
  $$ values ('1000000.00', '950000.00') $$,
  'a price change is logged with before and after'
);
select is(
  (select count(*) from public.audit_log, jsonb_object_keys(after)
   where table_name = 'properties' and action = 'update')::int,
  1,
  'an update logs only the changed field, not bookkeeping columns'
);
select is(
  (select user_id from public.audit_log where table_name = 'properties' and action = 'update'),
  'a2000000-0000-0000-0000-000000000000'::uuid,
  'the change log records who made the change'
);
select is(
  (select count(*) from public.audit_log where table_name = 'properties' and action = 'insert')::int,
  1,
  'creating a property is logged'
);
select ok(
  (select after ? 'deleted_at' from public.audit_log where table_name = 'persons' and action = 'update'),
  'moving a person to the trash is logged'
);
select is(
  (select after ->> 'role' from public.audit_log where table_name = 'profiles' and action = 'update'),
  'admin',
  'a role change is logged'
);
select ok(
  (select bool_and(not (after ? 'search_text') and not (after ? 'version'))
   from public.audit_log where after is not null),
  'bookkeeping columns are never logged'
);
select throws_ok($$ delete from public.audit_log $$, '42501', null, 'not even an admin can delete the change log');
select throws_ok($$ update public.audit_log set action = 'insert' $$, '42501', null, 'not even an admin can edit the change log');

-- ---------------------------------------------------------------- admin b1
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is(
  (select count(*) from public.audit_log where org_id = '0a000000-0000-0000-0000-000000000000')::int,
  0,
  'another office cannot read the change log'
);

-- ---------------------------------------------------------------- staff a2 after the role change of a3
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.audit_log)::int, 0, 'staff still cannot read it');

-- ---------------------------------------------------------------- anon
reset role;
set local role anon;
select throws_ok($$ select * from public.audit_log $$, '42501', null, 'anon cannot read the change log');

select * from finish();
rollback;
