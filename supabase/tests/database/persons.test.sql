-- RLS matrix for persons, status history, contact log and reminders (M1 step 4, rule 3).
-- Office A: admin a1, staff a2 and a3, inactive staff a4. Office B (suspended later): admin b1.
-- f1 is a platform admin. All data is synthetic and rolled back. CI only (ADR-0003).
begin;
create extension if not exists pgtap with schema extensions;
select plan(38);

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
insert into public.persons (id, org_id, owner_id, name, phone1_e164) values
  ('9a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000',
   'a2000000-0000-0000-0000-000000000000', 'Ayşe YILMAZ', '+905321112233'),
  ('9a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000',
   'a3000000-0000-0000-0000-000000000000', 'Can Kaya', null),
  ('9b100000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000',
   'b1000000-0000-0000-0000-000000000000', 'Deniz Ak', null);
insert into public.contact_log (org_id, person_id, channel, note) values
  ('0a000000-0000-0000-0000-000000000000', '9a300000-0000-0000-0000-000000000000', 'phone', 'Bütçe 2 M');
insert into public.reminders (org_id, user_id, person_id, due_date) values
  ('0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000',
   '9a300000-0000-0000-0000-000000000000', current_date);

-- ---------------------------------------------------------------- staff a2
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select id from public.persons $$,
  $$ values ('9a200000-0000-0000-0000-000000000000'::uuid) $$,
  'staff sees only their own persons'
);
select is((select count(*) from public.contact_log)::int, 0, 'staff sees no contact log of a colleague''s person');
select results_eq(
  $$ select person_id from public.person_status_history $$,
  $$ values ('9a200000-0000-0000-0000-000000000000'::uuid) $$,
  'staff sees status history of own persons only'
);
select is((select count(*) from public.reminders)::int, 0, 'staff sees no reminders of a colleague');

insert into public.persons (id, name) values ('9a210000-0000-0000-0000-000000000000', 'Mehmet Demir');
select results_eq(
  $$ select org_id, owner_id from public.persons where id = '9a210000-0000-0000-0000-000000000000' $$,
  $$ values ('0a000000-0000-0000-0000-000000000000'::uuid, 'a2000000-0000-0000-0000-000000000000'::uuid) $$,
  'a new person defaults to the caller''s office and ownership'
);
select throws_ok(
  $$ insert into public.persons (name, owner_id) values ('x', 'a3000000-0000-0000-0000-000000000000') $$,
  '42501', null, 'staff cannot create a person on a colleague''s name'
);
select throws_ok(
  $$ insert into public.persons (name, org_id) values ('x', '0b000000-0000-0000-0000-000000000000') $$,
  '42501', null, 'staff cannot create a person in another office'
);
-- Silently filtered by RLS; verified as the admin below
update public.persons set name = 'Hijacked' where id = '9a300000-0000-0000-0000-000000000000';
select throws_ok(
  $$ update public.persons set owner_id = 'a3000000-0000-0000-0000-000000000000'
     where id = '9a200000-0000-0000-0000-000000000000' $$,
  '42501', null, 'staff cannot hand a person over'
);
select throws_ok(
  $$ update public.persons set search_text = 'x' $$,
  '42501', null, 'search_text is server-maintained'
);
select throws_ok(
  $$ delete from public.persons where id = '9a200000-0000-0000-0000-000000000000' $$,
  '42501', null, 'clients cannot hard-delete persons'
);

update public.persons set client_status = 'searching' where id = '9a200000-0000-0000-0000-000000000000';
select results_eq(
  $$ select old_status, new_status from public.person_status_history
     where person_id = '9a200000-0000-0000-0000-000000000000' and old_status is not null $$,
  $$ values ('new', 'searching') $$,
  'a status change is recorded in the history'
);
select is(
  (select search_text from public.persons where id = '9a200000-0000-0000-0000-000000000000'),
  'ayşe yılmaz +905321112233',
  'search_text is the Turkish-normalized name and phone'
);

insert into public.contact_log (id, person_id, channel, note) values
  ('c2000000-0000-0000-0000-000000000000', '9a200000-0000-0000-0000-000000000000', 'whatsapp', 'Aradı');
select results_eq(
  $$ select owner_id, created_by from public.contact_log where id = 'c2000000-0000-0000-0000-000000000000' $$,
  $$ values ('a2000000-0000-0000-0000-000000000000'::uuid, 'a2000000-0000-0000-0000-000000000000'::uuid) $$,
  'contact log takes its owner from the person and its author from the session'
);
select throws_ok(
  $$ insert into public.contact_log (person_id, channel) values ('9a300000-0000-0000-0000-000000000000', 'phone') $$,
  '42501', null, 'staff cannot log contact with a colleague''s person'
);
select lives_ok(
  $$ insert into public.reminders (person_id, due_date) values ('9a200000-0000-0000-0000-000000000000', current_date) $$,
  'staff can set a reminder about their own person'
);
select throws_ok(
  $$ insert into public.reminders (person_id, due_date) values ('9a300000-0000-0000-0000-000000000000', current_date) $$,
  '42501', null, 'staff cannot set a reminder about a colleague''s person'
);
select throws_ok(
  $$ insert into public.reminders (user_id, due_date) values ('a3000000-0000-0000-0000-000000000000', current_date) $$,
  '42501', null, 'staff cannot assign reminders to colleagues'
);
select throws_ok(
  $$ insert into public.persons (name, phone1_e164) values ('x', '05321112233') $$,
  '23514', null, 'phones must be E.164'
);
select throws_ok(
  $$ insert into public.persons (name, roles) values ('x', '{buyer}') $$,
  '23514', null, 'roles are limited to owner and client'
);
update public.persons set deleted_at = now() where id = '9a210000-0000-0000-0000-000000000000';
select isnt(
  (select deleted_at from public.persons where id = '9a210000-0000-0000-0000-000000000000'),
  null,
  'staff can move their own person to the trash'
);

-- ---------------------------------------------------------------- admin a1
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is((select count(*) from public.persons)::int, 3, 'admin sees every person of the office and none of office B');
select is(
  (select name from public.persons where id = '9a300000-0000-0000-0000-000000000000'),
  'Can Kaya',
  'staff could not rename a colleague''s person'
);
select is((select count(*) from public.contact_log)::int, 2, 'admin sees every contact log of the office');
select is((select count(*) from public.reminders)::int, 2, 'admin sees every reminder of the office');
select lives_ok(
  $$ insert into public.persons (name, owner_id) values ('Admin için', 'a3000000-0000-0000-0000-000000000000') $$,
  'admin can create a person for a staff member'
);
select throws_ok(
  $$ update public.persons set owner_id = 'a2000000-0000-0000-0000-000000000000'
     where id = '9a300000-0000-0000-0000-000000000000' $$,
  '42501', null, 'not even an admin changes ownership directly (handover only)'
);
select lives_ok(
  $$ insert into public.reminders (user_id, person_id, due_date) values
     ('a3000000-0000-0000-0000-000000000000', '9a300000-0000-0000-0000-000000000000', current_date) $$,
  'admin can remind the owner about their person'
);
select throws_ok(
  $$ insert into public.reminders (user_id, person_id, due_date) values
     ('a2000000-0000-0000-0000-000000000000', '9a300000-0000-0000-0000-000000000000', current_date) $$,
  '42501', null, 'a reminder cannot expose a person to a staff member who does not own it'
);

-- ---------------------------------------------------------------- inactive a4
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is((select count(*) from public.persons)::int, 0, 'inactive user sees no persons');
select is((select count(*) from public.contact_log)::int, 0, 'inactive user sees no contact log');
select is((select count(*) from public.reminders)::int, 0, 'inactive user sees no reminders');

-- ---------------------------------------------------------------- admin b1, office B suspended
reset role;
update public.organizations set status = 'suspended' where id = '0b000000-0000-0000-0000-000000000000';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select results_eq(
  $$ select id from public.persons $$,
  $$ values ('9b100000-0000-0000-0000-000000000000'::uuid) $$,
  'office B sees only its own persons'
);
select throws_ok(
  $$ insert into public.persons (name) values ('x') $$,
  '42501', null, 'a suspended office cannot add persons'
);

-- ---------------------------------------------------------------- platform admin f1
select set_config('request.jwt.claims', '{"sub":"f1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select is((select count(*) from public.persons)::int, 0, 'platform admin sees no office persons (D-16)');

-- ---------------------------------------------------------------- anon
reset role;
set local role anon;
select throws_ok($$ select * from public.persons $$, '42501', null, 'anon cannot read persons');
select throws_ok($$ select * from public.person_status_history $$, '42501', null, 'anon cannot read status history');
select throws_ok($$ select * from public.contact_log $$, '42501', null, 'anon cannot read contact log');
select throws_ok($$ select * from public.reminders $$, '42501', null, 'anon cannot read reminders');

select * from finish();
rollback;
