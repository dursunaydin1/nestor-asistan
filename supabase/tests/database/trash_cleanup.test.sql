-- Trash rules and the nightly cleanup (M1 step 10, FR-ADM-05, FR-PER-06).
-- "old" rows were trashed 31 days ago, "new" ones 29 days ago. All data is synthetic and
-- rolled back. CI only (ADR-0003).
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000000', 'a1@example.test'),
  ('a2000000-0000-0000-0000-000000000000', 'a2@example.test');

insert into public.organizations (id, name) values ('0a000000-0000-0000-0000-000000000000', 'Office A');

insert into public.profiles (id, org_id, name, role) values
  ('a1000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Admin A', 'admin'),
  ('a2000000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'Staff A', 'staff');

insert into public.persons (id, org_id, owner_id, name, phone1_e164, email, deleted_at) values
  ('9a010000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
   'Eski Kişi', '+905321110001', 'eski@example.test', now() - interval '31 days'),
  ('9a020000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
   'Yeni Silinen', '+905321110002', null, now() - interval '29 days'),
  ('9a030000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
   'Canlı Kişi', null, null, null);

insert into public.contact_log (org_id, person_id, channel, note) values
  ('0a000000-0000-0000-0000-000000000000', '9a010000-0000-0000-0000-000000000000', 'phone', 'Kişisel not');

-- R1 belongs to the old (trashed) person but is itself live; R3 is a trashed request of a live person
insert into public.requests (id, org_id, person_id, kind, transactions, notes, deleted_at) values
  ('5a010000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', '9a010000-0000-0000-0000-000000000000',
   'residential', '{sale}', 'Gizli not', null),
  ('5a030000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', '9a030000-0000-0000-0000-000000000000',
   'land', '{sale}', null, now() - interval '31 days');

insert into public.properties (id, org_id, agent_id, kind, transactions, price_sale, deleted_at) values
  ('7a010000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
   'residential', '{sale}', 1000000, now() - interval '31 days'),
  ('7a020000-0000-0000-0000-000000000000', '0a000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000',
   'residential', '{sale}', 1000000, now() - interval '29 days');
insert into public.property_media (org_id, property_id, kind, storage_path, public_copy_path) values
  ('0a000000-0000-0000-0000-000000000000', '7a010000-0000-0000-0000-000000000000', 'photo', 'x1/1.webp', 'pub/1.webp');

insert into app.applied_ops (op_id, table_name, row_id, applied_at) values
  ('0c000000-0000-0000-0000-000000000001', 'public.persons', '9a030000-0000-0000-0000-000000000000', now() - interval '31 days'),
  ('0c000000-0000-0000-0000-000000000002', 'public.persons', '9a030000-0000-0000-0000-000000000000', now());

-- ---------------------------------------------------------------- the nightly run
select is(
  app.nightly_cleanup(),
  '{"properties": 1, "requests": 1, "persons_anonymised": 1}'::jsonb,
  'the run reports what it removed'
);
select is((select count(*) from public.properties where id = '7a010000-0000-0000-0000-000000000000')::int, 0, 'a property trashed 31 days ago is deleted');
select is((select count(*) from public.properties where id = '7a020000-0000-0000-0000-000000000000')::int, 1, 'a property trashed 29 days ago stays');
select results_eq(
  $$ select bucket, path from app.storage_purge_queue order by bucket $$,
  $$ values ('media', 'x1/1.webp'), ('public-media', 'pub/1.webp') $$,
  'its files are queued for removal from storage'
);
select is(
  (select name from public.persons where id = '9a010000-0000-0000-0000-000000000000'),
  '—',
  'an old person is anonymised, not deleted (FR-PER-06)'
);
select ok(
  (select phone1_e164 is null and email is null and anonymized_at is not null
   from public.persons where id = '9a010000-0000-0000-0000-000000000000'),
  'phone and e-mail are erased'
);
select is(
  (select name from public.persons where id = '9a020000-0000-0000-0000-000000000000'),
  'Yeni Silinen',
  'a person trashed 29 days ago is untouched'
);
select is(
  (select count(*) from public.contact_log where person_id = '9a010000-0000-0000-0000-000000000000')::int,
  0,
  'contact notes of the anonymised person are deleted'
);
select is(
  (select notes from public.requests where id = '5a010000-0000-0000-0000-000000000000'),
  null::text,
  'request notes of the anonymised person are erased, the request stays for statistics'
);
select is(
  (select count(*) from public.audit_log
   where table_name = 'persons' and row_id = '9a010000-0000-0000-0000-000000000000'
     and (before is not null or after is not null))::int,
  0,
  'the change log keeps no personal data of the anonymised person'
);
select is(
  (select count(*) from public.audit_log
   where table_name = 'requests' and row_id = '5a010000-0000-0000-0000-000000000000'
     and (before is not null or after is not null))::int,
  0,
  'nor of their requests'
);
select is((select count(*) from public.requests where id = '5a030000-0000-0000-0000-000000000000')::int, 0, 'an old trashed request is deleted');
select is((select count(*) from app.applied_ops)::int, 1, 'op claims older than 30 days are purged');
select is(
  app.nightly_cleanup(),
  '{"properties": 0, "requests": 0, "persons_anonymised": 0}'::jsonb,
  'a second run changes nothing'
);
select is((select count(*) from cron.job where jobname = 'nightly-cleanup')::int, 1, 'the job is scheduled nightly');

-- ---------------------------------------------------------------- restoring from the trash
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);

update public.persons set deleted_at = now() where id = '9a030000-0000-0000-0000-000000000000';
select throws_ok(
  $$ update public.persons set deleted_at = null where id = '9a030000-0000-0000-0000-000000000000' $$,
  '42501', null, 'staff cannot restore from the trash'
);
select throws_ok($$ select app.nightly_cleanup(now() + interval '1 year') $$, '42501', null, 'clients cannot run the cleanup');

select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select lives_ok(
  $$ update public.persons set deleted_at = null where id = '9a030000-0000-0000-0000-000000000000' $$,
  'an admin restores from the trash'
);

reset role;
set local role anon;
select throws_ok($$ select app.nightly_cleanup() $$, '42501', null, 'anon cannot run the cleanup');

select * from finish();
rollback;
