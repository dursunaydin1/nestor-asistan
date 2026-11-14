-- RLS matrix for requests, interests and matches (M1 step 6, rule 3, FR-MATCH-08).
-- Office A: admin a1, staff a2 and a3, inactive staff a4. Office B (suspended later): admin b1.
-- f1 is a platform admin. All data is synthetic and rolled back. CI only (ADR-0003).
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

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

-- P2 belongs to a2, P3 to a3, PB to b1
insert into public.persons (id, org_id, owner_id, name) values
  ('9a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'Ayşe Yılmaz'),
  ('9a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'Can Kaya'),
  ('9b100000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000000', 'Deniz Ak');

-- X2 is a2's property, X3 is a3's
insert into public.properties (id, org_id, agent_id, kind, transactions, price_sale) values
  ('7a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'residential', '{sale}', 1000000),
  ('7a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'residential', '{sale}', 2000000);

-- R2 is P2's request (a2), R3 is P3's request (a3)
insert into public.requests (id, org_id, person_id, kind, transactions, budget_max) values
  ('5a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', '9a200000-0000-0000-0000-000000000000', 'residential', '{sale}', 2500000),
  ('5a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', '9a300000-0000-0000-0000-000000000000', 'residential', '{sale}', 1200000);

-- M2: a2's client matches a3's property. M3: a3's client matches a2's property.
insert into public.matches (id, org_id, request_id, property_id, score) values
  ('3a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000',
   '5a200000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000', 90),
  ('3a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000',
   '5a300000-0000-0000-0000-000000000000', '7a200000-0000-0000-0000-000000000000', 88);

-- ---------------------------------------------------------------- staff a2
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select id from public.requests $$,
  $$ values ('5a200000-0000-0000-0000-000000000000'::uuid) $$,
  'staff sees only requests of own persons'
);
select results_eq(
  $$ select id from public.matches $$,
  $$ values ('3a200000-0000-0000-0000-000000000000'::uuid) $$,
  'the agent never sees a colleague''s match on their own property (FR-MATCH-08)'
);
select results_eq(
  $$ select match_id from public.match_status_history $$,
  $$ values ('3a200000-0000-0000-0000-000000000000'::uuid) $$,
  'match history follows match visibility'
);

insert into public.requests (id, person_id, kind, transactions)
values ('5a210000-0000-0000-0000-000000000000', '9a200000-0000-0000-0000-000000000000', 'land', '{sale}');
select is(
  (select owner_id from public.requests where id = '5a210000-0000-0000-0000-000000000000'),
  'a2000000-0000-0000-0000-000000000000'::uuid,
  'a request takes its owner from the person'
);
select throws_ok(
  $$ insert into public.requests (person_id, kind, transactions)
     values ('9a300000-0000-0000-0000-000000000000', 'land', '{sale}') $$,
  '42501', null, 'staff cannot open a request for a colleague''s person'
);
select throws_ok(
  $$ insert into public.matches (org_id, request_id, property_id, score)
     values ('0a000000-0000-0000-0000-000000000000', '5a200000-0000-0000-0000-000000000000',
             '7a200000-0000-0000-0000-000000000000', 99) $$,
  '42501', null, 'clients cannot create matches'
);

update public.matches set status = 'called' where id = '3a200000-0000-0000-0000-000000000000';
select results_eq(
  $$ select old_status, new_status from public.match_status_history
     where match_id = '3a200000-0000-0000-0000-000000000000' and old_status is not null $$,
  $$ values ('suggested', 'called') $$,
  'a match status change is recorded'
);
select throws_ok(
  $$ update public.matches set invalid_at = now() $$,
  '42501', null, 'only the system marks a match invalid'
);
select throws_ok(
  $$ update public.matches set score = 100 $$,
  '42501', null, 'clients cannot change the score'
);
select throws_ok(
  $$ update public.matches set status = 'invalid' where id = '3a200000-0000-0000-0000-000000000000' $$,
  '23514', null, 'invalid is not a workflow status'
);

select lives_ok(
  $$ insert into public.request_interests (person_id, property_id, request_id, source)
     values ('9a200000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000',
             '5a200000-0000-0000-0000-000000000000', 'call') $$,
  'staff links own client to any office property'
);
select throws_ok(
  $$ insert into public.request_interests (person_id, property_id)
     values ('9a300000-0000-0000-0000-000000000000', '7a200000-0000-0000-0000-000000000000') $$,
  '42501', null, 'staff cannot record interest for a colleague''s client'
);
select throws_ok(
  $$ insert into public.request_interests (person_id, property_id, request_id)
     values ('9a200000-0000-0000-0000-000000000000', '7a200000-0000-0000-0000-000000000000',
             '5a300000-0000-0000-0000-000000000000') $$,
  '23503', null, 'the request must belong to the same person'
);
select throws_ok(
  $$ insert into public.request_interests (person_id, property_id)
     values ('9a200000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000') $$,
  '23505', null, 'one interest per person and property'
);
select throws_ok(
  $$ insert into public.requests (person_id, kind, transactions, budget_min, budget_max)
     values ('9a200000-0000-0000-0000-000000000000', 'residential', '{sale}', 3000000, 2000000) $$,
  '23514', null, 'budget_min cannot exceed budget_max'
);
select throws_ok($$ select * from public.match_jobs $$, '42501', null, 'match jobs are server only');
select throws_ok(
  $$ delete from public.requests where id = '5a200000-0000-0000-0000-000000000000' $$,
  '42501', null, 'clients cannot hard-delete requests'
);

-- ---------------------------------------------------------------- staff a3
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select results_eq(
  $$ select id from public.matches $$,
  $$ values ('3a300000-0000-0000-0000-000000000000'::uuid) $$,
  'a3 sees the match of own client'
);

-- ---------------------------------------------------------------- admin a1
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.requests)::int, 3, 'admin sees every request of the office');
select is((select count(*) from public.matches)::int, 2, 'admin sees every match of the office');
update public.matches set status = 'shown' where id = '3a300000-0000-0000-0000-000000000000';
select is(
  (select status from public.matches where id = '3a300000-0000-0000-0000-000000000000'),
  'shown',
  'admin can move any match'
);

-- ---------------------------------------------------------------- inactive a4
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.requests)::int, 0, 'inactive user sees no requests');
select is((select count(*) from public.matches)::int, 0, 'inactive user sees no matches');

-- ---------------------------------------------------------------- admin b1, office B suspended
reset role;
update public.organizations set status = 'suspended' where id = '0b000000-0000-0000-0000-000000000000';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select throws_ok(
  $$ insert into public.requests (person_id, kind, transactions)
     values ('9b100000-0000-0000-0000-000000000000', 'land', '{sale}') $$,
  '42501', null, 'a suspended office cannot add requests'
);
select is((select count(*) from public.requests)::int, 0, 'office B sees none of office A''s requests');

-- ---------------------------------------------------------------- platform admin f1
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.matches)::int, 0, 'platform admin sees no matches (D-16)');

-- ---------------------------------------------------------------- anon
reset role;
set local role anon;
select throws_ok($$ select * from public.requests $$, '42501', null, 'anon cannot read requests');
select throws_ok($$ select * from public.request_interests $$, '42501', null, 'anon cannot read interests');
select throws_ok($$ select * from public.matches $$, '42501', null, 'anon cannot read matches');
select throws_ok($$ select * from public.match_status_history $$, '42501', null, 'anon cannot read match history');
select throws_ok($$ select * from public.match_jobs $$, '42501', null, 'anon cannot read match jobs');

select * from finish();
rollback;
