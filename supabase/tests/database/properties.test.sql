-- RLS matrix for properties and their private/child tables (M1 step 5, PRD §6, rule 2).
-- Office A: admin a1, staff a2 and a3, inactive staff a4. Office B (suspended later): admin b1.
-- f1 is a platform admin. All data is synthetic and rolled back. CI only (ADR-0003).
begin;
create extension if not exists pgtap with schema extensions;
select plan(44);

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

-- Persons: P2 and P2c belong to a2, P3 to a3
insert into public.persons (id, org_id, owner_id, name, roles) values
  ('9a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'Ayşe Yılmaz', '{owner}'),
  ('9a2c0000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'Ali Yılmaz', '{owner}'),
  ('9a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'Can Kaya', '{owner}');

-- Properties: X2 by a2 (code 1), X3 by a3 (code 2), XB by b1
insert into public.properties (id, org_id, agent_id, kind, transactions, price_sale, price_rent) values
  ('7a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
   'residential', '{sale}', 1000000, null),
  ('7a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000',
   'residential', '{rent}', null, 20000),
  ('7b100000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000000',
   'land', '{sale}', 500000, null);

insert into public.property_private (id, org_id, min_price_sale, min_price_rent) values
  ('7a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 900000, null),
  ('7a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', null, 18000);
insert into public.property_owners (org_id, property_id, person_id, is_contact) values
  ('0a000000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000', '9a300000-0000-0000-0000-000000000000', true);
insert into public.property_media (org_id, property_id, kind, storage_path) values
  ('0a000000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000', 'photo', 'x3/1.webp'),
  ('0a000000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000', 'doc', 'x3/tapu.pdf');

-- ---------------------------------------------------------------- staff a2
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is((select count(*) from public.properties)::int, 2, 'staff sees the whole office portfolio and nothing of office B');
select results_eq(
  $$ select id from public.property_private $$,
  $$ values ('7a200000-0000-0000-0000-000000000000'::uuid) $$,
  'staff sees private fields of own properties only'
);
select is((select count(*) from public.property_owners)::int, 0, 'staff cannot see owners of a colleague''s property');
select results_eq(
  $$ select kind from public.property_media where property_id = '7a300000-0000-0000-0000-000000000000' $$,
  $$ values ('photo') $$,
  'staff sees a colleague''s photos but not their documents'
);
select is(
  (select count(*) from public.property_private_history where property_id = '7a300000-0000-0000-0000-000000000000')::int,
  0,
  'staff cannot see private history of a colleague''s property'
);
select is(
  (select count(*) from public.property_price_history where property_id = '7a300000-0000-0000-0000-000000000000')::int,
  1,
  'listing price history is office-wide'
);

-- Silently filtered by RLS; verified as the admin below
update public.properties set price_rent = 1 where id = '7a300000-0000-0000-0000-000000000000';
select throws_ok(
  $$ insert into public.property_private (id, min_price_rent) values ('7a300000-0000-0000-0000-000000000000', 1) $$,
  '42501', null, 'staff cannot write private fields of a colleague''s property'
);
select throws_ok(
  $$ insert into public.property_media (property_id, kind, storage_path)
     values ('7a300000-0000-0000-0000-000000000000', 'photo', 'x') $$,
  '42501', null, 'staff cannot add media to a colleague''s property'
);

update public.properties set price_sale = 950000 where id = '7a200000-0000-0000-0000-000000000000';
select results_eq(
  $$ select price_kind, old_price, new_price from public.property_price_history
     where property_id = '7a200000-0000-0000-0000-000000000000' and old_price is not null $$,
  $$ values ('sale', 1000000.00::numeric, 950000.00::numeric) $$,
  'a price change is recorded'
);
update public.properties set status = 'optioned' where id = '7a200000-0000-0000-0000-000000000000';
select results_eq(
  $$ select old_status, new_status from public.property_status_history
     where property_id = '7a200000-0000-0000-0000-000000000000' and old_status is not null $$,
  $$ values ('active', 'optioned') $$,
  'a status change is recorded'
);

insert into public.properties (id, kind, transactions, price_sale)
values ('7a210000-0000-0000-0000-000000000000', 'commercial', '{sale,rent}', 3000000);
select is(
  (select code from public.properties where id = '7a210000-0000-0000-0000-000000000000'),
  3,
  'codes are assigned per office in order'
);
select throws_ok(
  $$ insert into public.properties (kind, transactions, price_sale, agent_id)
     values ('residential', '{sale}', 1, 'a3000000-0000-0000-0000-000000000000') $$,
  '42501', null, 'staff cannot create a property for a colleague'
);
select throws_ok(
  $$ update public.properties set agent_id = 'a3000000-0000-0000-0000-000000000000'
     where id = '7a200000-0000-0000-0000-000000000000' $$,
  '42501', null, 'the agent changes only through handover'
);
select throws_ok(
  $$ insert into public.properties (kind, transactions, price_sale, code) values ('residential', '{sale}', 1, 99) $$,
  '42501', null, 'clients cannot choose the code'
);
select throws_ok(
  $$ insert into public.properties (kind, transactions) values ('residential', '{sale}') $$,
  '23514', null, 'a sale needs a sale price'
);
select throws_ok(
  $$ insert into public.properties (kind, transactions, price_sale) values ('residential', '{auction}', 1) $$,
  '23514', null, 'unknown transactions are rejected'
);
select lives_ok(
  $$ insert into public.properties (kind, transactions) values ('land', '{swap}') $$,
  'swap needs no price'
);
select throws_ok(
  $$ delete from public.properties where id = '7a200000-0000-0000-0000-000000000000' $$,
  '42501', null, 'clients cannot hard-delete properties'
);

select lives_ok(
  $$ insert into public.property_owners (property_id, person_id, is_contact)
     values ('7a200000-0000-0000-0000-000000000000', '9a200000-0000-0000-0000-000000000000', true) $$,
  'agent links an own person as owner'
);
select throws_ok(
  $$ insert into public.property_owners (property_id, person_id)
     values ('7a200000-0000-0000-0000-000000000000', '9a300000-0000-0000-0000-000000000000') $$,
  '42501', null, 'a colleague''s client cannot be attached as owner'
);
select throws_ok(
  $$ insert into public.property_owners (property_id, person_id, is_contact)
     values ('7a200000-0000-0000-0000-000000000000', '9a2c0000-0000-0000-0000-000000000000', true) $$,
  '23505', null, 'only one contact person per property'
);

update public.property_private set min_price_sale = 920000 where id = '7a200000-0000-0000-0000-000000000000';
select results_eq(
  $$ select field, old_value, new_value from public.property_private_history
     where property_id = '7a200000-0000-0000-0000-000000000000' and old_value is not null $$,
  $$ values ('min_price_sale', '900000.00', '920000.00') $$,
  'a private field change is recorded'
);

insert into public.property_change_requests (property_id, note)
values ('7a300000-0000-0000-0000-000000000000', 'Fiyat değişmiş');
-- Not the agent: filtered by RLS, verified as a3 below
update public.property_change_requests set status = 'done';
select lives_ok(
  $$ insert into public.reminders (property_id, due_date) values ('7a300000-0000-0000-0000-000000000000', current_date) $$,
  'staff can set a reminder about any office property'
);

-- ---------------------------------------------------------------- staff a3 (agent of X3)
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select note, status from public.property_change_requests $$,
  $$ values ('Fiyat değişmiş', 'open') $$,
  'the agent sees the request, still open'
);
update public.property_change_requests set status = 'done';
select is(
  (select status from public.property_change_requests),
  'done',
  'the agent closes the request'
);
select results_eq(
  $$ select id from public.property_private $$,
  $$ values ('7a300000-0000-0000-0000-000000000000'::uuid) $$,
  'a3 sees only own private fields'
);

-- ---------------------------------------------------------------- admin a1
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is((select count(*) from public.property_private)::int, 2, 'admin sees every private row of the office');
select is(
  (select price_rent from public.properties where id = '7a300000-0000-0000-0000-000000000000'),
  20000.00::numeric,
  'staff could not change a colleague''s price'
);
select is(
  (select count(*) from public.property_media where property_id = '7a300000-0000-0000-0000-000000000000')::int,
  2,
  'admin sees documents too'
);
select is((select count(*) from public.property_owners)::int, 2, 'admin sees every owner link');
update public.properties set price_rent = 21000 where id = '7a300000-0000-0000-0000-000000000000';
select is(
  (select price_rent from public.properties where id = '7a300000-0000-0000-0000-000000000000'),
  21000.00::numeric,
  'admin can edit any office property'
);
select is((select count(*) from public.properties)::int, 4, 'admin sees the office portfolio and nothing of office B');

-- ---------------------------------------------------------------- inactive a4
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.properties)::int, 0, 'inactive user sees no properties');

-- ---------------------------------------------------------------- admin b1, office B suspended
reset role;
update public.organizations set status = 'suspended' where id = '0b000000-0000-0000-0000-000000000000';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select code from public.properties $$,
  $$ values (1) $$,
  'office B sees only its own property, numbered from 1'
);
select throws_ok(
  $$ insert into public.properties (kind, transactions) values ('land', '{swap}') $$,
  '42501', null, 'a suspended office cannot add properties'
);

-- ---------------------------------------------------------------- platform admin f1
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.properties)::int, 0, 'platform admin sees no office properties (D-16)');

-- ---------------------------------------------------------------- anon
reset role;
set local role anon;
select throws_ok($$ select * from public.properties $$, '42501', null, 'anon cannot read properties');
select throws_ok($$ select * from public.property_private $$, '42501', null, 'anon cannot read private fields');
select throws_ok($$ select * from public.property_private_history $$, '42501', null, 'anon cannot read private history');
select throws_ok($$ select * from public.property_owners $$, '42501', null, 'anon cannot read owners');
select throws_ok($$ select * from public.property_media $$, '42501', null, 'anon cannot read media');
select throws_ok($$ select * from public.property_price_history $$, '42501', null, 'anon cannot read price history');
select throws_ok($$ select * from public.property_status_history $$, '42501', null, 'anon cannot read status history');
select throws_ok($$ select * from public.property_change_requests $$, '42501', null, 'anon cannot read change requests');

select * from finish();
rollback;
