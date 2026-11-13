-- Foundation helpers and shared triggers (M1 step 1). Runs in CI only (ADR-0003).
-- Text cases mirror packages/shared/src/text.test.ts so client and server agree.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

select has_extension('pgcrypto', 'pgcrypto is installed');
select has_extension('pg_net', 'pg_net is installed');
select has_extension('pg_cron', 'pg_cron is installed');

-- Turkish text
select is(app.tr_lower('İSTANBUL'), 'istanbul', 'dotted capital I becomes i');
select is(app.tr_lower('IĞDIR'), 'ığdır', 'dotless capital I becomes ı');
select is(
  app.tr_lower('ÇANAKKALE ŞİLE ÜSKÜDAR ÖDEMİŞ'),
  'çanakkale şile üsküdar ödemiş',
  'Turkish capitals are lowercased regardless of collation'
);
select is(app.tr_lower('KÂĞITHANE'), 'kâğıthane', 'circumflex letters are lowercased');
select is(app.normalize_tr(E'  Kadıköy \t  Merkez '), 'kadıköy merkez', 'trims and collapses whitespace');
select is(
  app.normalize_tr(U&'Ba\0067\0306c\0131lar'),
  app.normalize_tr('Bağcılar'),
  'decomposed and composed characters match'
);
select is(app.search_text('Kadıköy', null, 'MODA'), 'kadıköy moda', 'search_text skips nulls');

-- Shared triggers on scratch tables (rolled back)
insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'user-a@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'user-b@example.test');

create schema app_test;
create table app_test.rows (
  id uuid primary key,
  title text not null,
  version integer not null default 1,
  created_at timestamptz,
  created_by uuid,
  updated_at timestamptz,
  updated_by uuid
);
create trigger touch before insert or update on app_test.rows
  for each row execute function app.touch_row();

create table app_test.parents (id uuid primary key, kaydeden_user_id uuid not null);
create table app_test.children (
  id uuid primary key,
  parent_id uuid not null,
  kaydeden_user_id uuid not null
);
create trigger copy_owner before insert or update on app_test.children
  for each row execute function app.copy_parent_owner('app_test.parents', 'parent_id');

insert into app_test.parents values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

grant usage on schema app_test to authenticated;
grant select, insert, update on all tables in schema app_test to authenticated;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

insert into app_test.rows (id, title, version, created_by, updated_by)
values (
  'bbbbbbbb-0000-0000-0000-000000000001', 'first', 99,
  '22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222'
);
select is(
  (select version from app_test.rows),
  1,
  'insert ignores the client version'
);
select is(
  (select created_by from app_test.rows),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'insert ignores a forged created_by'
);

select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
update app_test.rows
set title = 'second', version = 50, created_by = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select version, created_by, updated_by from app_test.rows $$,
  $$ values (2, '11111111-1111-1111-1111-111111111111'::uuid, '22222222-2222-2222-2222-222222222222'::uuid) $$,
  'update bumps the version by one and keeps the creator'
);

insert into app_test.children values (
  'cccccccc-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  '22222222-2222-2222-2222-222222222222'
);
select is(
  (select kaydeden_user_id from app_test.children),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'child owner is copied from the parent, not taken from the client'
);
select throws_ok(
  $$ insert into app_test.children values (
       'cccccccc-0000-0000-0000-000000000002',
       'aaaaaaaa-0000-0000-0000-00000000ffff',
       '22222222-2222-2222-2222-222222222222') $$,
  '23502',
  null,
  'a child of an unknown or hidden parent is rejected'
);

select lives_ok($$ select app.tr_lower('x') $$, 'authenticated can call text helpers');

-- Anonymous
reset role;
set local role anon;
select throws_ok($$ select app.tr_lower('x') $$, '42501', null, 'anon cannot use the app schema');
select is(
  (select count(*) from information_schema.routines where routine_schema = 'app')::int,
  0,
  'anon cannot even list app functions'
);

select * from finish();
rollback;
