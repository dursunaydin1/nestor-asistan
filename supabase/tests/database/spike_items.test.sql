-- RLS and write-path tests for the sync spike table (runs in CI only, ADR-0003).
-- Synthetic users; the transaction is rolled back at the end.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'user-a@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'user-b@example.test');

-- User A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  (select public.spike_upsert('aaaaaaaa-0000-0000-0000-000000000001', 'A first', false, null) -> 'overwritten'),
  'false'::jsonb,
  'A creates an item without an overwrite'
);
select is((select count(*) from public.spike_items)::int, 1, 'A sees own item');
select is(
  (select version from public.spike_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1,
  'server assigns version 1 on insert'
);
select is(
  (select public.spike_upsert('aaaaaaaa-0000-0000-0000-000000000001', 'A second', false, 1) -> 'item' -> 'version'),
  '2'::jsonb,
  'update from the current version bumps to 2'
);
select is(
  (select public.spike_upsert('aaaaaaaa-0000-0000-0000-000000000001', 'A stale', false, 1) -> 'overwritten'),
  'true'::jsonb,
  'update from a stale version still wins and reports overwritten'
);
select is(
  (select title from public.spike_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'A stale',
  'last write wins'
);
-- Separate statement: a query cannot see rows changed by a function it calls (same snapshot)
select public.spike_upsert('aaaaaaaa-0000-0000-0000-000000000001', 'A stale', true, 3);
select isnt(
  (select deleted_at from public.spike_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  null,
  'soft delete sets deleted_at'
);
update public.spike_items set version = 100 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is(
  (select version from public.spike_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  5,
  'client cannot set version; the trigger assigns it'
);

-- User B
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is((select count(*) from public.spike_items)::int, 0, 'B cannot see A items');
select throws_ok(
  $$ select public.spike_upsert('aaaaaaaa-0000-0000-0000-000000000001', 'B hijack', false, 4) $$,
  '23505',
  null,
  'B cannot overwrite A item through the write path'
);
select throws_ok(
  $$ insert into public.spike_items (id, owner_id, title)
     values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'as A') $$,
  '42501',
  null,
  'B cannot insert a row owned by A'
);
select throws_ok(
  $$ delete from public.spike_items $$,
  '42501',
  null,
  'clients cannot hard-delete'
);

-- Anonymous
reset role;
set local role anon;
select throws_ok($$ select * from public.spike_items $$, '42501', null, 'anon has no access');

select * from finish();
rollback;
