-- M1 step 10: trash rules and the nightly cleanup (FR-ADM-05, FR-PER-06, data-model §8.4).
-- Soft-deleted rows stay 30 days; only admins restore them. After 30 days records are deleted,
-- except persons, which are anonymised so match/viewing statistics survive (FR-PER-06).
-- Read views of non-deleted rows were dropped from the plan: they freeze their column list (step 3
-- adds region columns) and a `deleted_at is null` filter gives the same result under the same RLS.

-- ---------------------------------------------------------------------------------------------
-- Only admins restore from the trash (FR-ADM-05)
-- ---------------------------------------------------------------------------------------------

create function app.guard_restore() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Server jobs (no JWT) may restore; clients only when admin
  if old.deleted_at is not null and new.deleted_at is null
    and auth.uid() is not null and not app.is_admin() then
    raise exception 'only an admin can restore from the trash' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger guard_restore before update of deleted_at on public.persons
  for each row execute function app.guard_restore();
create trigger guard_restore before update of deleted_at on public.properties
  for each row execute function app.guard_restore();
create trigger guard_restore before update of deleted_at on public.requests
  for each row execute function app.guard_restore();
create trigger guard_restore before update of deleted_at on public.contact_log
  for each row execute function app.guard_restore();
create trigger guard_restore before update of deleted_at on public.reminders
  for each row execute function app.guard_restore();
create trigger guard_restore before update of deleted_at on public.property_owners
  for each row execute function app.guard_restore();
create trigger guard_restore before update of deleted_at on public.property_media
  for each row execute function app.guard_restore();
create trigger guard_restore before update of deleted_at on public.request_interests
  for each row execute function app.guard_restore();

-- ---------------------------------------------------------------------------------------------
-- Nightly cleanup
-- ---------------------------------------------------------------------------------------------

-- FR-PER-06: the UI shows the anonymised name from tr.json when this is set
alter table public.persons add column anonymized_at timestamptz;

-- Files can only be removed through the Storage API; an Edge Function drains this queue
create table app.storage_purge_queue (
  id bigint generated always as identity primary key,
  bucket text not null,
  path text not null,
  queued_at timestamptz not null default now()
);
alter table app.storage_purge_queue enable row level security;
revoke all on app.storage_purge_queue from public, anon, authenticated;

create function app.nightly_cleanup(p_now timestamptz default now()) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cutoff timestamptz := p_now - interval '30 days';
  removed_properties integer;
  removed_requests integer;
  anonymised_persons integer;
  removed_requests_ids uuid[];
  anonymised_ids uuid[];
begin
  -- Files of media rows that are about to disappear, directly or with their property
  insert into app.storage_purge_queue (bucket, path)
  select 'media', m.storage_path
  from public.property_media m
  join public.properties p on p.id = m.property_id
  where m.deleted_at < cutoff or p.deleted_at < cutoff
  union all
  select 'public-media', m.public_copy_path
  from public.property_media m
  join public.properties p on p.id = m.property_id
  where (m.deleted_at < cutoff or p.deleted_at < cutoff) and m.public_copy_path is not null;

  delete from public.property_media where deleted_at < cutoff;
  delete from public.property_owners where deleted_at < cutoff;
  delete from public.properties where deleted_at < cutoff;
  get diagnostics removed_properties = row_count;
  delete from public.request_interests where deleted_at < cutoff;
  delete from public.reminders where deleted_at < cutoff;
  delete from public.contact_log where deleted_at < cutoff;

  with gone as (
    delete from public.requests where deleted_at < cutoff returning id
  )
  select array_agg(id) into removed_requests_ids from gone;
  removed_requests := coalesce(cardinality(removed_requests_ids), 0);

  -- Persons: personal fields go, the row stays for statistics (FR-PER-06)
  with anonymised as (
    update public.persons
    set name = '—',
        phone1_e164 = null,
        phone2_e164 = null,
        email = null,
        source = null,
        notes = null,
        anonymized_at = p_now
    where deleted_at < cutoff and anonymized_at is null
    returning id
  )
  select array_agg(id) into anonymised_ids from anonymised;
  anonymised_persons := coalesce(cardinality(anonymised_ids), 0);

  if anonymised_persons > 0 then
    delete from public.contact_log where person_id = any (anonymised_ids);
    update public.requests set notes = null where person_id = any (anonymised_ids);
  end if;

  -- The change log must not keep what was just erased
  update public.audit_log
  set before = null, after = null
  where (table_name = 'persons' and row_id = any (coalesce(anonymised_ids, '{}')))
     or (table_name = 'requests' and row_id = any (coalesce(removed_requests_ids, '{}')))
     or (
       table_name = 'requests'
       and row_id in (select r.id from public.requests r where r.person_id = any (coalesce(anonymised_ids, '{}')))
     );

  -- Outbox retries never come back after 30 days (ADR-0001)
  delete from app.applied_ops where applied_at < cutoff;

  return jsonb_build_object(
    'properties', removed_properties,
    'requests', removed_requests,
    'persons_anonymised', anonymised_persons
  );
end;
$$;

-- 01:00 UTC = 04:00 Europe/Istanbul
select cron.schedule('nightly-cleanup', '0 1 * * *', $$select app.nightly_cleanup()$$);

-- Platform-wide defaults grant EXECUTE on new functions to anon (see 20261113140100)
revoke execute on all functions in schema app from public, anon;
-- The cleanup takes a date: a client calling it with a future date could purge the trash early.
-- The app schema is not exposed through the API, but only the cron job (postgres) may run it.
revoke execute on function app.nightly_cleanup(timestamptz) from authenticated, service_role;
