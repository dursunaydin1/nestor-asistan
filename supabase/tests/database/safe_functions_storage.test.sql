-- Safe functions and storage path rules (M1 step 9, FR-PER-02, FR-PROP-22, PRD §6).
-- Office A: admin a1, staff a2 and a3, inactive staff a4. Office B (suspended later): admin b1.
-- All data is synthetic and rolled back. CI only (ADR-0003).
begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000000', 'a1@example.test'),
  ('a2000000-0000-0000-0000-000000000000', 'a2@example.test'),
  ('a3000000-0000-0000-0000-000000000000', 'a3@example.test'),
  ('a4000000-0000-0000-0000-000000000000', 'a4@example.test'),
  ('b1000000-0000-0000-0000-000000000000', 'b1@example.test');

insert into public.organizations (id, name) values
  ('0a000000-0000-0000-0000-000000000000', 'Office A'),
  ('0b000000-0000-0000-0000-000000000000', 'Office B');

insert into public.profiles (id, org_id, name, role, is_active) values
  ('a1000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Admin A', 'admin', true),
  ('a2000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Staff A', 'staff', true),
  ('a3000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Staff A2', 'staff', true),
  ('a4000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Former A', 'staff', false),
  ('b1000000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000', 'Admin B', 'admin', true);

insert into public.persons (id, org_id, owner_id, name, phone1_e164) values
  ('9a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'Ayşe Yılmaz', '+905321110002'),
  ('9a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'Can Kaya', '+905321110003'),
  ('9b100000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000000', 'Deniz Ak', '+905321110009');

insert into public.properties (id, org_id, agent_id, kind, transactions, price_sale) values
  ('7a200000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'residential', '{sale}', 1000000),
  ('7a300000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a3000000-0000-0000-0000-000000000000', 'residential', '{sale}', 2000000),
  ('7b100000-0000-0000-0000-000000000000', '0b000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000000', 'land', '{sale}', 500000);

-- Two clients asked about X3, one about XB
insert into public.request_interests (org_id, person_id, property_id) values
  ('0a000000-0000-0000-0000-000000000000', '9a200000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000'),
  ('0a000000-0000-0000-0000-000000000000', '9a300000-0000-0000-0000-000000000000', '7a300000-0000-0000-0000-000000000000'),
  ('0b000000-0000-0000-0000-000000000000', '9b100000-0000-0000-0000-000000000000', '7b100000-0000-0000-0000-000000000000');

-- ---------------------------------------------------------------- staff a2
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is(public.check_phone_conflict('+905321110002') ->> 'status', 'mine', 'own client is reported as mine');
select is(
  public.check_phone_conflict('+905321110003'),
  '{"status": "other", "owner_name": "Staff A2"}'::jsonb,
  'a colleague''s client is reported by the colleague''s name only'
);
select is(public.check_phone_conflict('+905321119999') ->> 'status', 'none', 'unknown number');
select is(public.check_phone_conflict('+905321110009') ->> 'status', 'none', 'another office''s client is invisible');
select throws_ok(
  $$ select public.check_phone_conflict('0532 111 00 02') $$,
  '22023', null, 'the phone must already be E.164'
);
select is(public.property_interest_count('7a300000-0000-0000-0000-000000000000'), 2, 'interest count of an office property');
select is(public.property_interest_count('7b100000-0000-0000-0000-000000000000'), 0, 'another office''s property counts as zero');

select ok(app.can_read_media('0a000000-0000-0000-0000-000000000000/properties/7a300000-0000-0000-0000-000000000000/photo/1.webp'), 'staff sees photos of any office property');
select ok(not app.can_read_media('0a000000-0000-0000-0000-000000000000/properties/7a300000-0000-0000-0000-000000000000/doc/tapu.pdf'), 'staff cannot open a colleague''s documents');
select ok(app.can_read_media('0a000000-0000-0000-0000-000000000000/properties/7a200000-0000-0000-0000-000000000000/doc/tapu.pdf'), 'the agent opens own documents');
select ok(app.can_write_media('0a000000-0000-0000-0000-000000000000/properties/7a200000-0000-0000-0000-000000000000/photo/2.webp'), 'the agent uploads to own property');
select ok(not app.can_write_media('0a000000-0000-0000-0000-000000000000/properties/7a300000-0000-0000-0000-000000000000/photo/2.webp'), 'staff cannot upload to a colleague''s property');
select ok(not app.can_write_media('0a000000-0000-0000-0000-000000000000/org/logo.webp'), 'staff cannot replace the office logo');
select ok(not app.can_read_media('0b000000-0000-0000-0000-000000000000/properties/7b100000-0000-0000-0000-000000000000/photo/1.webp'), 'another office''s files are invisible');
select ok(not app.can_read_media('0a000000-0000-0000-0000-000000000000/properties/not-a-uuid/photo/1.webp'), 'a malformed path is refused, not an error');
select ok(not app.can_write_media('0a000000-0000-0000-0000-000000000000/properties/7a200000-0000-0000-0000-000000000000/secret/x.bin'), 'unknown folders are refused');

-- ---------------------------------------------------------------- admin a1
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is(
  (select count(*) from public.notifications where kind = 'phone_conflict')::int,
  1,
  'the admin is told about the conflict'
);
select ok(
  (select not (payload ?| array['name', 'phone1_e164', 'person_id', 'email'])
   from public.notifications where kind = 'phone_conflict'),
  'the conflict notification carries no client details'
);
select ok(app.can_write_media('0a000000-0000-0000-0000-000000000000/org/logo.webp'), 'the admin uploads the office logo');
select is(public.check_phone_conflict('+905321110003') ->> 'status', 'mine', 'the admin sees every office client as own');

-- ---------------------------------------------------------------- inactive a4
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select throws_ok($$ select public.check_phone_conflict('+905321110002') $$, '42501', null, 'an inactive user cannot probe numbers');
select ok(not app.can_read_media('0a000000-0000-0000-0000-000000000000/properties/7a200000-0000-0000-0000-000000000000/photo/1.webp'), 'an inactive user opens no files');

-- ---------------------------------------------------------------- admin b1, office B suspended
reset role;
update public.organizations set status = 'suspended' where id = '0b000000-0000-0000-0000-000000000000';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

select is(public.property_interest_count('7b100000-0000-0000-0000-000000000000'), 1, 'office B counts its own interests');
select ok(not app.can_write_media('0b000000-0000-0000-0000-000000000000/properties/7b100000-0000-0000-0000-000000000000/photo/1.webp'), 'a suspended office cannot upload');

-- ---------------------------------------------------------------- anon
reset role;
set local role anon;
select throws_ok($$ select public.check_phone_conflict('+905321110002') $$, '42501', null, 'anon cannot probe numbers');
select throws_ok($$ select public.property_interest_count('7a300000-0000-0000-0000-000000000000') $$, '42501', null, 'anon cannot count interests');

-- ---------------------------------------------------------------- buckets
reset role;
select is((select public from storage.buckets where id = 'media'), false, 'the media bucket is private');
select is((select public from storage.buckets where id = 'public-media'), true, 'the public-media bucket is public');
select is(
  (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'media\_%')::int,
  4,
  'media has select, insert, update and delete policies'
);

select * from finish();
rollback;
