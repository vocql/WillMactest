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
  -- Appeals: the staff member who issued the punishment can't decide it (name is answer #3 of the appeal).
  if p_status in ('approved','denied') and length(coalesce(public.staff_name(staff_key), '')) >= 3 and exists (
    select 1 from public.applications
    where id::text = any(p_ids) and type = 'appeal'
      and lower(coalesce(answers->>2, '')) like '%' || lower(public.staff_name(staff_key)) || '%'
  ) then return -3; end if;
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

-- APPEALS: after a denial, the same Discord account has to wait 7 days before sending another one.
create or replace function public.appeal_cooldown_guard()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.type = 'appeal' and new.discord_id is not null and exists (
    select 1 from public.applications
    where type = 'appeal' and discord_id = new.discord_id and status = 'denied'
      and coalesce(status_at, created_at) > now() - interval '7 days'
  ) then raise exception 'appeal_cooldown'; end if;
  return new;
end $$;
drop trigger if exists zz_appeal_cooldown on public.applications;
create trigger zz_appeal_cooldown before insert on public.applications
  for each row execute function public.appeal_cooldown_guard();

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

notify pgrst, 'reload schema';


-- ---------------------------------------------------------------
-- RESULT FEEDBACK
-- Members rate a decided result (approved / denied) from "My applications". They can send it anonymously:
-- then no name is stored. Only a one-way code is kept so nobody can send twice for the same result.
-- Staff (any role) read it in the pinned Feedback folder; admins can delete it.
-- ---------------------------------------------------------------
create table if not exists public.feedback (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  app_type   text not null,
  outcome    text not null check (outcome in ('approved','denied')),
  message    text not null,
  anonymous  boolean not null default false,
  name       text,
  limit_key  text not null unique
);
-- If you ran an older version of this file (thumbs up/down), this upgrades the table to written reviews.
alter table public.feedback drop column if exists rating;
alter table public.feedback drop constraint if exists feedback_message_check;
alter table public.feedback alter column message set not null;
update public.feedback set message = 'No written review' where message is null;
alter table public.feedback add constraint feedback_message_check check (char_length(message) between 1 and 1000);
alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;

drop function if exists public.submit_feedback(uuid, text, text, boolean);
create or replace function public.submit_feedback(p_app_id uuid, p_message text, p_anonymous boolean)
returns text language plpgsql security definer set search_path = public
as $$
declare did text; a public.applications; k text; n int; m text;
begin
  did := public.my_discord_id();
  if did is null then return 'login'; end if;
  m := left(trim(coalesce(p_message, '')), 1000);
  if char_length(m) < 20 then return 'short'; end if;
  select * into a from public.applications where id = p_app_id and discord_id = did;
  if not found then return 'notfound'; end if;
  if a.status not in ('approved','denied') then return 'notdecided'; end if;
  k := encode(sha256(convert_to(did || ':' || p_app_id::text, 'utf8')), 'hex');
  insert into public.feedback (app_type, outcome, message, anonymous, name, limit_key)
  values (a.type, a.status, m, coalesce(p_anonymous, false),
          case when coalesce(p_anonymous, false) then null else left(a.discord_name, 100) end, k)
  on conflict (limit_key) do nothing;
  get diagnostics n = row_count;
  return case when n = 0 then 'duplicate' else 'ok' end;
end $$;

create or replace function public.my_feedback_given()
returns text[] language sql stable security definer set search_path = public
as $$
  select coalesce(array_agg(a.id::text), '{}') from public.applications a
  where public.my_discord_id() is not null and a.discord_id = public.my_discord_id()
    and exists (select 1 from public.feedback f
                where f.limit_key = encode(sha256(convert_to(a.discord_id || ':' || a.id::text, 'utf8')), 'hex'))
$$;

drop function if exists public.list_feedback(text);
create or replace function public.list_feedback(staff_key text)
returns table (id bigint, created_at timestamptz, app_type text, outcome text, message text, anonymous boolean, name text)
language sql stable security definer set search_path = public
as $$
  select f.id, f.created_at, f.app_type, f.outcome, f.message, f.anonymous, f.name
  from public.feedback f where public.staff_role(staff_key) is not null
  order by f.created_at desc limit 500
$$;

create or replace function public.delete_feedback(staff_key text, p_id bigint)
returns boolean language plpgsql security definer set search_path = public
as $$
begin
  if public.staff_role(staff_key) is distinct from 'admin' then return false; end if;
  delete from public.feedback where id = p_id;
  perform public.log_action(staff_key, 'deleted', 'feedback #' || p_id);
  return true;
end $$;
