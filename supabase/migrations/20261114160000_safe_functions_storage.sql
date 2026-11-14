-- M1 step 9: safe functions that answer without exposing details, and storage buckets with
-- path-based policies (FR-PER-02, FR-PROP-22, FR-PROP-17, PRD §6, data-model §8.3).

-- ---------------------------------------------------------------------------------------------
-- Safe functions
-- ---------------------------------------------------------------------------------------------

-- FR-PER-02: is this number already in the office? A colleague's client is reported by the
-- colleague's name only, and admins get a notification without the client's details.
-- Volatile because it writes notifications.
create function public.check_phone_conflict(p_phone text) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  org uuid := app.current_org_id();
  own_person uuid;
  other_owner uuid;
  other_name text;
begin
  if org is null then
    raise exception 'no active office' using errcode = '42501';
  end if;
  if p_phone is null or p_phone !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'phone must be E.164' using errcode = '22023';
  end if;

  select p.id into own_person
  from public.persons p
  where p.org_id = org
    and p.deleted_at is null
    and p_phone in (p.phone1_e164, p.phone2_e164)
    and (p.owner_id = caller or app.is_admin())
  limit 1;
  if own_person is not null then
    return jsonb_build_object('status', 'mine', 'person_id', own_person);
  end if;

  select p.owner_id, pr.name into other_owner, other_name
  from public.persons p
  join public.profiles pr on pr.id = p.owner_id
  where p.org_id = org
    and p.deleted_at is null
    and p_phone in (p.phone1_e164, p.phone2_e164)
  limit 1;
  if other_owner is null then
    return jsonb_build_object('status', 'none');
  end if;

  insert into public.notifications (org_id, user_id, kind, payload)
  select org, a.id, 'phone_conflict',
         jsonb_build_object('requested_by', caller, 'owner_id', other_owner)
  from public.profiles a
  where a.org_id = org and a.role = 'admin' and a.is_active and a.id <> caller;

  return jsonb_build_object('status', 'other', 'owner_name', other_name);
end;
$$;

-- FR-PROP-22: the agent sees how many people asked about a property, never who
create function public.property_interest_count(p_property_id uuid) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.request_interests i
  where i.property_id = p_property_id
    and i.org_id = app.current_org_id()
    and i.deleted_at is null
$$;

revoke all on function public.check_phone_conflict(text), public.property_interest_count(uuid)
  from public, anon;
grant execute on function public.check_phone_conflict(text), public.property_interest_count(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Storage
-- media (private):  {org_id}/org/{file}                                   office logo
--                   {org_id}/properties/{property_id}/{photo|video|doc}/{file}
-- public-media:     copies for public pages, written only by the server (M10)
-- ---------------------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('media', 'media', false, 52428800,
   array['image/jpeg', 'image/webp', 'image/png', 'video/mp4', 'video/quicktime', 'application/pdf']),
  ('public-media', 'public-media', true, 5242880, array['image/jpeg', 'image/webp']);

-- Path checks never raise: a malformed path is simply not allowed
create function app.media_path_property(p_name text) returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when (storage.foldername(p_name))[2] = 'properties'
      and (storage.foldername(p_name))[3] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then ((storage.foldername(p_name))[3])::uuid
  end
$$;

create function app.can_read_media(p_name text) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (storage.foldername(p_name))[1] = app.current_org_id()::text
    and case (storage.foldername(p_name))[2]
      when 'org' then true
      when 'properties' then
        app.media_path_property(p_name) is not null
        and (
          (storage.foldername(p_name))[4] in ('photo', 'video')
          or ((storage.foldername(p_name))[4] = 'doc' and app.can_edit_property(app.media_path_property(p_name)))
        )
      else false
    end,
    false
  )
$$;

create function app.can_write_media(p_name text) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (storage.foldername(p_name))[1] = app.current_org_id()::text
    and app.org_is_writable()
    and case (storage.foldername(p_name))[2]
      when 'org' then app.is_admin()
      when 'properties' then
        (storage.foldername(p_name))[4] in ('photo', 'video', 'doc')
        and app.media_path_property(p_name) is not null
        and app.can_edit_property(app.media_path_property(p_name))
      else false
    end,
    false
  )
$$;

grant execute on function
  app.media_path_property(text), app.can_read_media(text), app.can_write_media(text)
  to authenticated, service_role;

create policy media_select on storage.objects
  for select to authenticated
  using (bucket_id = 'media' and app.can_read_media(name));
create policy media_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and app.can_write_media(name));
create policy media_update on storage.objects
  for update to authenticated
  using (bucket_id = 'media' and app.can_write_media(name))
  with check (bucket_id = 'media' and app.can_write_media(name));
create policy media_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and app.can_write_media(name));

-- Platform-wide defaults grant EXECUTE on new functions to anon (see 20261113140100)
revoke execute on all functions in schema app from public, anon;
