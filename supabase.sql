-- Run this in Supabase: SQL Editor > New query > paste everything > Run.
-- Safe to run again. Upgrades older versions (types, review status, per-person staff logins, activity log).

create table if not exists public.applications (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  discord_name text not null check (char_length(discord_name) between 1 and 100),
  answers      jsonb not null check (
                 jsonb_typeof(answers) = 'array'
                 and jsonb_array_length(answers) between 1 and 30
                 and pg_column_size(answers) < 40000
               )
);

alter table public.applications add column if not exists type text not null default 'mod';
alter table public.applications drop constraint if exists applications_type_check;
alter table public.applications add constraint applications_type_check check (type ~ '^[a-z0-9_-]{1,30}$');

alter table public.applications add column if not exists status text not null default 'pending';
alter table public.applications drop constraint if exists applications_status_check;
alter table public.applications add constraint applications_status_check
  check (status in ('pending','in_review','interview','more_info','on_hold','approved','denied'));

-- Progress bar info shown to the applicant.
alter table public.applications add column if not exists reviewer    text;
alter table public.applications add column if not exists status_note text;
alter table public.applications add column if not exists status_at   timestamptz;

-- Every status change is kept here (shown as "Progress history").
create table if not exists public.application_history (
  id             bigint generated always as identity primary key,
  application_id uuid not null references public.applications(id) on delete cascade,
  at             timestamptz not null default now(),
  status         text not null,
  reviewer       text,
  note           text,
  actor          text
);
create index if not exists application_history_app on public.application_history (application_id, at);
alter table public.application_history enable row level security;
revoke all on public.application_history from anon, authenticated;

alter table public.applications add column if not exists discord_id text;
drop index if exists public.applications_one_pending;
create unique index if not exists applications_one_pending on public.applications (discord_id, type)
  where status in ('pending','in_review','interview','more_info','on_hold') and discord_id is not null;

alter table public.applications enable row level security;

drop policy if exists "staff can view" on public.applications;
drop policy if exists "anyone can view" on public.applications;
drop function if exists public.is_staff();
drop function if exists public.get_statuses(text);

-- ---------------------------------------------------------------
-- STAFF ACCESS
-- Roles: viewer (read only) / reviewer (approve + deny) / admin (everything).
-- Admins create a separate login code per person from the dashboard (Staff button).
-- Codes are stored hashed, so they can't be read back. Use "New code" if one is lost.
-- ---------------------------------------------------------------
create table if not exists public.staff_users (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 40),
  role       text not null default 'viewer' check (role in ('viewer','reviewer','admin')),
  code_hash  text not null unique,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  last_used  timestamptz
);
create table if not exists public.staff_log (
  id     bigserial primary key,
  at     timestamptz not null default now(),
  actor  text not null,
  action text not null,
  detail text
);
alter table public.staff_users enable row level security;
alter table public.staff_log enable row level security;
revoke all on public.staff_users from anon, authenticated;
revoke all on public.staff_log from anon, authenticated;

-- ---------------------------------------------------------------
-- DISCORD ROLE LOGIN FOR STAFF (no bot needed)
-- Staff log in with Discord. The database asks Discord directly which roles that person has in your
-- server, then gives them dashboard access based on the table below. Highest role wins.
--   admin    = everything (open/close, delete, manage logins)
--   reviewer = read + approve/deny
--   viewer   = read only
-- To change who gets what, edit the rows below and run this file again.
-- ---------------------------------------------------------------
do $$ begin
  create extension if not exists http with schema extensions;
exception when others then
  raise notice 'Could not enable the http extension. Turn it on in Supabase > Database > Extensions (search "http"), then run this file again.';
end $$;

create table if not exists public.discord_role_map (
  role_id text primary key check (role_id ~ '^[0-9]{5,25}$'),
  label   text not null,
  access  text not null check (access in ('none','viewer','reviewer','admin'))
);
alter table public.discord_role_map drop constraint if exists discord_role_map_access_check;
alter table public.discord_role_map add constraint discord_role_map_access_check check (access in ('none','viewer','reviewer','admin'));
alter table public.discord_role_map enable row level security;
revoke all on public.discord_role_map from anon, authenticated;

insert into public.discord_role_map (role_id, label, access) values
  ('1402003322633719953', 'Owner',     'admin'),
  ('1402003409028255804', 'Admin',     'admin'),
  ('1544535384355110953', 'Lead Mod',  'reviewer'),
  ('1496649340478029844', 'Mod',       'viewer')
on conflict (role_id) do update set label = excluded.label, access = excluded.access;

-- Per-person access by Discord ID (on top of roles). The highest of role / person wins.
-- Voqcl (the owner) is also hard-coded as admin inside staff_login_discord, so can't be removed.
create table if not exists public.staff_overrides (
  discord_id text primary key check (discord_id ~ '^[0-9]{5,25}$'),
  name       text not null check (char_length(name) between 1 and 40),
  access     text not null check (access in ('viewer','reviewer','admin')),
  created_at timestamptz not null default now()
);
alter table public.staff_overrides enable row level security;
revoke all on public.staff_overrides from anon, authenticated;
insert into public.staff_overrides (discord_id, name, access) values ('1271246652421701633', 'Voqcl', 'admin')
on conflict (discord_id) do update set access = 'admin';

create table if not exists public.staff_sessions (
  key_hash   text primary key,
  discord_id text not null,
  name       text not null,
  role       text not null check (role in ('viewer','reviewer','admin')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
alter table public.staff_sessions enable row level security;
revoke all on public.staff_sessions from anon, authenticated;

-- OWNER KEY: your original login. It always has admin access, so you can never lock yourself out.
-- Change 'macstaff-7x4kq' below (it appears only once) once you have made your own admin code.
create or replace function public.is_master(k text)
returns boolean language sql stable security definer set search_path = public
as $$ select lower(trim(coalesce(k, ''))) = 'macstaff-7x4kq' $$;

create or replace function public.code_hash(k text)
returns text language sql immutable set search_path = public
as $$ select encode(sha256(convert_to(lower(trim(coalesce(k, ''))), 'utf8')), 'hex') $$;

create or replace function public.staff_role(staff_key text)
returns text language sql stable security definer set search_path = public
as $$
  select case when public.is_master(staff_key) then 'admin'
    else coalesce(
      (select role from public.staff_sessions where key_hash = public.code_hash(staff_key) and expires_at > now()),
      (select role from public.staff_users where active and code_hash = public.code_hash(staff_key))) end
$$;

create or replace function public.staff_name(staff_key text)
returns text language sql stable security definer set search_path = public
as $$
  select case when public.is_master(staff_key) then 'Owner'
    else coalesce(
      (select name from public.staff_sessions where key_hash = public.code_hash(staff_key) and expires_at > now()),
      (select name from public.staff_users where code_hash = public.code_hash(staff_key))) end
$$;

create or replace function public.is_staff(staff_key text)
returns boolean language sql stable security definer set search_path = public
as $$ select public.staff_role(staff_key) is not null $$;

create or replace function public.staff_login(staff_key text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare r text;
begin
  r := public.staff_role(staff_key);
  if r is null then return null; end if;
  if not public.is_master(staff_key) then
    update public.staff_users set last_used = now() where active and code_hash = public.code_hash(staff_key);
  end if;
  return jsonb_build_object('role', r, 'name', public.staff_name(staff_key));
end $$;

create or replace function public.log_action(staff_key text, p_action text, p_detail text)
returns void language sql security definer set search_path = public
as $$
  insert into public.staff_log (actor, action, detail)
  values (coalesce(public.staff_name(staff_key), '?'), p_action, left(coalesce(p_detail, ''), 500))
$$;

-- On/off switch per application type (admin only).
create table if not exists public.app_settings (
  type_id text primary key check (type_id ~ '^[a-z0-9_-]{1,30}$'),
  is_open boolean not null default true
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;

create or replace function public.type_is_open(t text)
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select is_open from public.app_settings where type_id = t), true) $$;

create or replace function public.get_closed_types()
returns text[] language sql stable security definer set search_path = public
as $$ select coalesce(array_agg(type_id order by type_id), '{}') from public.app_settings where not is_open $$;

create or replace function public.set_type_open(staff_key text, p_type text, p_open boolean)
returns boolean language plpgsql security definer set search_path = public
as $$
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return false; end if;
  insert into public.app_settings (type_id, is_open) values (p_type, p_open)
  on conflict (type_id) do update set is_open = excluded.is_open;
  perform public.log_action(staff_key, case when p_open then 'opened' else 'closed' end, p_type || ' applications');
  return true;
end $$;

-- Any role can read.
create or replace function public.list_applications(staff_key text)
returns setof public.applications language sql stable security definer set search_path = public
as $$
  select * from public.applications
  where public.staff_role(staff_key) is not null
  order by created_at desc
  limit 2000
$$;

-- Reviewer or admin (approve / deny buttons). Returns count, -1 = bad login/input, -2 = role not allowed.
create or replace function public.set_application_status(staff_key text, p_ids text[], p_status text)
returns integer language plpgsql security definer set search_path = public
as $$
declare n int; r text; names text;
begin
  r := public.staff_role(staff_key);
  if r is null then return -1; end if;
  if r not in ('reviewer','admin') then return -2; end if;
  if p_status not in ('pending','approved','denied') then return -1; end if;
  select string_agg(discord_name, ', ') into names from public.applications where id::text = any(p_ids);
  insert into public.application_history (application_id, status, reviewer, note, actor)
    select id, p_status, reviewer, null, public.staff_name(staff_key) from public.applications where id::text = any(p_ids);
  update public.applications set status = p_status, status_at = now() where id::text = any(p_ids);
  get diagnostics n = row_count;
  if n > 0 then perform public.log_action(staff_key, p_status, n || ' application(s): ' || coalesce(names, '')); end if;
  return n;
end $$;

-- Reviewer or admin: set the progress bar status, who is handling it, and a message for the applicant.
-- With several ids at once (bulk), reviewer and message are left as they are.
create or replace function public.set_application_progress(staff_key text, p_ids text[], p_status text, p_reviewer text, p_note text)
returns integer language plpgsql security definer set search_path = public
as $$
declare n int; r text; names text; rv text; nt text; single boolean;
begin
  r := public.staff_role(staff_key);
  if r is null then return -1; end if;
  if r not in ('reviewer','admin') then return -2; end if;
  if p_status not in ('pending','in_review','interview','more_info','on_hold','approved','denied') then return -1; end if;
  single := coalesce(array_length(p_ids, 1), 0) = 1;
  rv := nullif(left(trim(coalesce(p_reviewer, '')), 40), '');
  nt := nullif(left(trim(coalesce(p_note, '')), 300), '');
  select string_agg(discord_name, ', ') into names from public.applications where id::text = any(p_ids);
  if single then
    insert into public.application_history (application_id, status, reviewer, note, actor)
      select id, p_status, rv, nt, public.staff_name(staff_key) from public.applications where id::text = any(p_ids);
    update public.applications set status = p_status, reviewer = rv, status_note = nt, status_at = now()
      where id::text = any(p_ids);
  else
    insert into public.application_history (application_id, status, reviewer, note, actor)
      select id, p_status, reviewer, null, public.staff_name(staff_key) from public.applications where id::text = any(p_ids);
    update public.applications set status = p_status, status_at = now() where id::text = any(p_ids);
  end if;
  get diagnostics n = row_count;
  if n > 0 then perform public.log_action(staff_key, 'progress: ' || p_status, n || ' application(s): ' || coalesce(names, '')); end if;
  return n;
end $$;

-- Any staff role can read the history of one application.
create or replace function public.list_application_history(staff_key text, p_id text)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
begin
  if public.staff_role(staff_key) is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.at desc) from
    (select at, status, reviewer, note, actor from public.application_history where application_id::text = p_id) x), '[]'::jsonb);
end $$;

-- Admin only.
create or replace function public.delete_applications(staff_key text, p_ids text[])
returns integer language plpgsql security definer set search_path = public
as $$
declare n int; r text; names text;
begin
  r := public.staff_role(staff_key);
  if r is null then return -1; end if;
  if r <> 'admin' then return -2; end if;
  select string_agg(discord_name, ', ') into names from public.applications where id::text = any(p_ids);
  delete from public.applications where id::text = any(p_ids);
  get diagnostics n = row_count;
  if n > 0 then perform public.log_action(staff_key, 'deleted', n || ' application(s): ' || coalesce(names, '')); end if;
  return n;
end $$;

-- Admin only: manage logins.
create or replace function public.list_staff(staff_key text)
returns jsonb language plpgsql security definer set search_path = public
as $$
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id::text, 'name', name, 'role', role,
    'active', active, 'created_at', created_at, 'last_used', last_used) order by created_at) from public.staff_users), '[]'::jsonb);
end $$;

create or replace function public.create_staff(staff_key text, p_name text, p_role text)
returns text language plpgsql security definer set search_path = public
as $$
declare nm text := trim(coalesce(p_name, '')); code text;
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return null; end if;
  if char_length(nm) < 1 or char_length(nm) > 40 then return null; end if;
  if p_role not in ('viewer','reviewer','admin') then return null; end if;
  code := 'wm-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 20);
  insert into public.staff_users (name, role, code_hash) values (nm, p_role, public.code_hash(code));
  perform public.log_action(staff_key, 'created login', nm || ' (' || p_role || ')');
  return code;
end $$;

create or replace function public.update_staff(staff_key text, p_id text, p_role text, p_active boolean)
returns boolean language plpgsql security definer set search_path = public
as $$
declare nm text;
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return false; end if;
  if p_role is not null and p_role not in ('viewer','reviewer','admin') then return false; end if;
  update public.staff_users set role = coalesce(p_role, role), active = coalesce(p_active, active)
  where id::text = p_id returning name into nm;
  if not found then return false; end if;
  perform public.log_action(staff_key, 'changed login',
    nm || ':' || coalesce(' role ' || p_role, '') ||
    case when p_active is null then '' when p_active then ' restored' else ' revoked' end);
  return true;
end $$;

create or replace function public.reset_staff_code(staff_key text, p_id text)
returns text language plpgsql security definer set search_path = public
as $$
declare nm text; code text;
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return null; end if;
  code := 'wm-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 20);
  update public.staff_users set code_hash = public.code_hash(code) where id::text = p_id returning name into nm;
  if not found then return null; end if;
  perform public.log_action(staff_key, 'reset code', nm);
  return code;
end $$;

create or replace function public.delete_staff(staff_key text, p_id text)
returns boolean language plpgsql security definer set search_path = public
as $$
declare nm text;
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return false; end if;
  delete from public.staff_users where id::text = p_id returning name into nm;
  if not found then return false; end if;
  perform public.log_action(staff_key, 'removed login', nm);
  return true;
end $$;

create or replace function public.list_log(staff_key text)
returns jsonb language plpgsql security definer set search_path = public
as $$
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from
    (select at, actor, action, detail from public.staff_log order by id desc limit 200) x), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------
-- DISCORD LOGIN
-- Applicants log in with Discord (Supabase Auth). Their real Discord ID comes from auth.identities,
-- which they cannot edit, and is stamped onto every application by a trigger. Nobody can fake it.
-- ---------------------------------------------------------------
create or replace function public.my_discord_id()
returns text language sql stable security definer set search_path = public, auth
as $$ select i.provider_id from auth.identities i where i.user_id = auth.uid() and i.provider = 'discord' limit 1 $$;

create or replace function public.stamp_discord_id()
returns trigger language plpgsql security definer set search_path = public
as $$ begin new.discord_id := public.my_discord_id(); return new; end $$;

drop trigger if exists applications_stamp_discord on public.applications;
create trigger applications_stamp_discord before insert on public.applications
  for each row execute function public.stamp_discord_id();

-- Only the logged-in person's own applications (status, progress info, history and answers).
drop function if exists public.my_applications();
create or replace function public.my_applications()
returns table (id uuid, created_at timestamptz, type text, status text, answers jsonb,
               reviewer text, status_note text, status_at timestamptz, history jsonb)
language sql stable security definer set search_path = public
as $$
  select a.id, a.created_at, a.type, a.status, a.answers, a.reviewer, a.status_note, a.status_at,
         coalesce((select jsonb_agg(jsonb_build_object('at', h.at, 'status', h.status, 'reviewer', h.reviewer, 'note', h.note) order by h.at)
                   from public.application_history h where h.application_id = a.id), '[]'::jsonb)
  from public.applications a
  where public.my_discord_id() is not null and a.discord_id = public.my_discord_id()
  order by a.created_at desc
$$;

-- Only people logged in with Discord can apply, and only while that type is open (insert only).
drop policy if exists "anyone can apply" on public.applications;
drop policy if exists "discord users can apply" on public.applications;
create policy "discord users can apply" on public.applications
  for insert to authenticated with check (public.type_is_open(type) and public.my_discord_id() is not null);

grant usage on schema public to anon, authenticated;
revoke all on public.applications from anon, authenticated;
grant insert on public.applications to authenticated;

-- Discord staff login. The website sends the person's Discord token; we ask Discord for their roles in
-- the server and hand back a short-lived session key (8 hours) that the dashboard uses like a staff code.
create or replace function public.staff_login_discord(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions
as $$
declare
  guild constant text := '1402002569965867008';
  owner_id constant text := '1271246652421701633';
  resp extensions.http_response;
  j jsonb; rank int := 0; r_rank int := null; m record;
  uid text; nm text; k text; r text;
begin
  if p_token is null or char_length(p_token) < 10 or char_length(p_token) > 300 then
    return jsonb_build_object('error', 'bad_token');
  end if;
  begin
    resp := extensions.http((
      'GET',
      'https://discord.com/api/v10/users/@me/guilds/' || guild || '/member',
      array[extensions.http_header('Authorization', 'Bearer ' || p_token),
            extensions.http_header('User-Agent', 'DiscordBot (willmac-mod-apps, 1.0)')],
      null, null)::extensions.http_request);
  exception when others then
    return jsonb_build_object('error', 'discord_unreachable');
  end;
  if resp.status in (401, 403) then return jsonb_build_object('error', 'bad_token'); end if;
  if resp.status = 404 then return jsonb_build_object('error', 'not_in_server'); end if;
  if resp.status <> 200 then return jsonb_build_object('error', 'discord_error', 'status', resp.status); end if;
  j := resp.content::jsonb;

  uid := j->'user'->>'id';
  if uid is null then return jsonb_build_object('error', 'discord_error'); end if;

  for m in select d.access from public.discord_role_map d
           where d.access <> 'none'
             and d.role_id in (select jsonb_array_elements_text(coalesce(j->'roles', '[]'::jsonb)))
  loop
    r_rank := case m.access when 'admin' then 3 when 'reviewer' then 2 else 1 end;
    if r_rank > rank then rank := r_rank; end if;
  end loop;
  select case o.access when 'admin' then 3 when 'reviewer' then 2 else 1 end into r_rank
    from public.staff_overrides o where o.discord_id = uid;
  if r_rank is not null and r_rank > rank then rank := r_rank; end if;
  if uid = owner_id then rank := 3; end if;
  if rank = 0 then return jsonb_build_object('error', 'no_role'); end if;
  r := case rank when 3 then 'admin' when 2 then 'reviewer' else 'viewer' end;
  nm  := left(coalesce(nullif(j->>'nick', ''), nullif(j->'user'->>'global_name', ''), j->'user'->>'username', 'Staff'), 40);

  delete from public.staff_sessions where expires_at < now() or discord_id = uid;
  k := 'ds-' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.staff_sessions (key_hash, discord_id, name, role, expires_at)
  values (public.code_hash(k), uid, nm, r, now() + interval '8 hours');
  perform public.log_action(k, 'discord login', nm || ' (' || r || ')');
  return jsonb_build_object('key', k, 'role', r, 'name', nm);
end $$;

create or replace function public.staff_logout(staff_key text)
returns void language sql security definer set search_path = public
as $$ delete from public.staff_sessions where key_hash = public.code_hash(staff_key) $$;

-- Admin only: see and change what each Discord role / person can do. Others are signed out so it applies at once.
create or replace function public.list_access(staff_key text)
returns jsonb language plpgsql security definer set search_path = public
as $$
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return null; end if;
  return jsonb_build_object(
    'roles',  coalesce((select jsonb_agg(jsonb_build_object('role_id', role_id, 'label', label, 'access', access) order by label) from public.discord_role_map), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(jsonb_build_object('discord_id', discord_id, 'name', name, 'access', access) order by name) from public.staff_overrides), '[]'::jsonb));
end $$;

create or replace function public.set_role_access(staff_key text, p_role_id text, p_access text)
returns boolean language plpgsql security definer set search_path = public
as $$
declare lb text;
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return false; end if;
  if p_access not in ('none','viewer','reviewer','admin') then return false; end if;
  update public.discord_role_map set access = p_access where role_id = p_role_id returning label into lb;
  if not found then return false; end if;
  delete from public.staff_sessions where key_hash <> public.code_hash(staff_key);
  perform public.log_action(staff_key, 'role access', lb || ' -> ' || p_access);
  return true;
end $$;

-- p_access null removes the person. The owner can't be changed or removed.
create or replace function public.set_person_access(staff_key text, p_discord_id text, p_name text, p_access text)
returns boolean language plpgsql security definer set search_path = public
as $$
declare did text := trim(coalesce(p_discord_id, '')); nm text := trim(coalesce(p_name, ''));
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return false; end if;
  if did !~ '^[0-9]{5,25}$' or did = '1271246652421701633' then return false; end if;
  if p_access is null then
    delete from public.staff_overrides where discord_id = did;
    perform public.log_action(staff_key, 'person access', 'removed ' || did);
  else
    if p_access not in ('viewer','reviewer','admin') or char_length(nm) not between 1 and 40 then return false; end if;
    insert into public.staff_overrides (discord_id, name, access) values (did, nm, p_access)
    on conflict (discord_id) do update set name = excluded.name, access = excluded.access;
    perform public.log_action(staff_key, 'person access', nm || ' (' || did || ') -> ' || p_access);
  end if;
  delete from public.staff_sessions where key_hash <> public.code_hash(staff_key);
  return true;
end $$;

-- Internal helpers: not callable from the website.
revoke all on function public.is_master(text) from public, anon, authenticated;
revoke all on function public.code_hash(text) from public, anon, authenticated;
revoke all on function public.staff_name(text) from public, anon, authenticated;
revoke all on function public.log_action(text, text, text) from public, anon, authenticated;

grant execute on function public.is_staff(text) to anon, authenticated;
grant execute on function public.staff_role(text) to anon, authenticated;
grant execute on function public.staff_login(text) to anon, authenticated;
grant execute on function public.staff_login_discord(text) to anon, authenticated;
grant execute on function public.staff_logout(text) to anon, authenticated;
grant execute on function public.list_access(text) to anon, authenticated;
grant execute on function public.set_role_access(text, text, text) to anon, authenticated;
grant execute on function public.set_person_access(text, text, text, text) to anon, authenticated;
grant execute on function public.type_is_open(text) to anon, authenticated;
grant execute on function public.get_closed_types() to anon, authenticated;
grant execute on function public.set_type_open(text, text, boolean) to anon, authenticated;
grant execute on function public.list_applications(text) to anon, authenticated;
grant execute on function public.set_application_status(text, text[], text) to anon, authenticated;
grant execute on function public.set_application_progress(text, text[], text, text, text) to anon, authenticated;
grant execute on function public.list_application_history(text, text) to anon, authenticated;
grant execute on function public.delete_applications(text, text[]) to anon, authenticated;
grant execute on function public.list_staff(text) to anon, authenticated;
grant execute on function public.create_staff(text, text, text) to anon, authenticated;
grant execute on function public.update_staff(text, text, text, boolean) to anon, authenticated;
grant execute on function public.reset_staff_code(text, text) to anon, authenticated;
grant execute on function public.delete_staff(text, text) to anon, authenticated;
grant execute on function public.list_log(text) to anon, authenticated;

revoke all on function public.my_discord_id() from public, anon;
revoke all on function public.my_applications() from public, anon;
grant execute on function public.my_discord_id() to authenticated;
grant execute on function public.my_applications() to authenticated;

-- ---------------------------------------------------------------
-- MEMBER INFO (profile shown on the staff dashboard)
-- When an applicant logs in with Discord, the site hands their Discord token to record_member_info().
-- The database asks Discord itself (so it can't be faked), checks the answer is really that person,
-- and saves joined date, nickname, boosting, username, display name and avatar.
-- ---------------------------------------------------------------
create table if not exists public.member_info (
  discord_id     text primary key,
  joined_at      timestamptz,
  nick           text,
  boosting_since timestamptz,
  updated_at     timestamptz not null default now()
);
alter table public.member_info add column if not exists username text;
alter table public.member_info add column if not exists global_name text;
alter table public.member_info add column if not exists avatar_url text;
alter table public.member_info enable row level security;
revoke all on public.member_info from anon, authenticated;

create or replace function public.record_member_info(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, auth
as $$
declare
  guild constant text := '1402002569965867008';
  me text; resp extensions.http_response; j jsonb; av text;
begin
  me := public.my_discord_id();
  if me is null then return jsonb_build_object('error', 'not_logged_in'); end if;
  if p_token is null or char_length(p_token) < 10 or char_length(p_token) > 300 then
    return jsonb_build_object('error', 'bad_token');
  end if;
  begin
    resp := extensions.http((
      'GET',
      'https://discord.com/api/v10/users/@me/guilds/' || guild || '/member',
      array[extensions.http_header('Authorization', 'Bearer ' || p_token),
            extensions.http_header('User-Agent', 'DiscordBot (willmac-mod-apps, 1.0)')],
      null, null)::extensions.http_request);
  exception when others then
    return jsonb_build_object('error', 'discord_unreachable');
  end;
  if resp.status = 404 then return jsonb_build_object('error', 'not_in_server'); end if;
  if resp.status <> 200 then return jsonb_build_object('error', 'discord_error', 'status', resp.status); end if;
  j := resp.content::jsonb;
  if (j->'user'->>'id') is distinct from me then return jsonb_build_object('error', 'mismatch'); end if;

  -- server avatar first, then global avatar, then Discord's default one
  av := case
    when nullif(j->>'avatar', '') is not null
      then 'https://cdn.discordapp.com/guilds/' || guild || '/users/' || me || '/avatars/' || (j->>'avatar') || '.png?size=128'
    when nullif(j->'user'->>'avatar', '') is not null
      then 'https://cdn.discordapp.com/avatars/' || me || '/' || (j->'user'->>'avatar') || '.png?size=128'
    else 'https://cdn.discordapp.com/embed/avatars/' || (((me::bigint) >> 22) % 6) || '.png'
  end;

  insert into public.member_info (discord_id, joined_at, nick, boosting_since, username, global_name, avatar_url, updated_at)
  values (me,
          nullif(j->>'joined_at', '')::timestamptz,
          left(nullif(j->>'nick', ''), 60),
          nullif(j->>'premium_since', '')::timestamptz,
          left(j->'user'->>'username', 60),
          left(nullif(j->'user'->>'global_name', ''), 60),
          av,
          now())
  on conflict (discord_id) do update
    set joined_at = excluded.joined_at, nick = excluded.nick, boosting_since = excluded.boosting_since,
        username = excluded.username, global_name = excluded.global_name, avatar_url = excluded.avatar_url,
        updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- Staff (any role) can read it, same as list_applications.
-- People whose join date was never recorded still get their name and profile picture, taken from the
-- Discord login itself (auth.identities, which they can't edit). Join date needs their Discord token,
-- so it appears once they log in again.
drop function if exists public.list_member_info(text);
create or replace function public.list_member_info(staff_key text)
returns table (discord_id text, joined_at timestamptz, nick text, boosting_since timestamptz,
               username text, global_name text, avatar_url text)
language sql stable security definer set search_path = public, auth
as $$
  select m.discord_id, m.joined_at, m.nick, m.boosting_since, m.username, m.global_name, m.avatar_url
  from public.member_info m
  where public.staff_role(staff_key) is not null
  union all
  select i.provider_id, null::timestamptz, null::text, null::timestamptz,
         left(i.identity_data->>'name', 60),
         left(nullif(i.identity_data->'custom_claims'->>'global_name', ''), 60),
         case when (i.identity_data->>'avatar_url') like 'https://cdn.discordapp.com/%' then i.identity_data->>'avatar_url' end
  from auth.identities i
  where public.staff_role(staff_key) is not null
    and i.provider = 'discord'
    and i.provider_id in (select a.discord_id from public.applications a where a.discord_id is not null)
    and not exists (select 1 from public.member_info m2 where m2.discord_id = i.provider_id)
$$;

revoke all on function public.record_member_info(text) from public, anon;
grant execute on function public.record_member_info(text) to authenticated;
grant execute on function public.list_member_info(text) to anon, authenticated;

notify pgrst, 'reload schema';
