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
alter table public.applications add constraint applications_status_check check (status in ('pending','approved','denied'));

alter table public.applications add column if not exists discord_id text;
create unique index if not exists applications_one_pending on public.applications (discord_id, type)
  where status = 'pending' and discord_id is not null;

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
    else (select role from public.staff_users where active and code_hash = public.code_hash(staff_key)) end
$$;

create or replace function public.staff_name(staff_key text)
returns text language sql stable security definer set search_path = public
as $$
  select case when public.is_master(staff_key) then 'Owner'
    else (select name from public.staff_users where code_hash = public.code_hash(staff_key)) end
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

-- Reviewer or admin. Returns count, -1 = bad login/input, -2 = role not allowed.
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
  update public.applications set status = p_status where id::text = any(p_ids);
  get diagnostics n = row_count;
  if n > 0 then perform public.log_action(staff_key, p_status, n || ' application(s): ' || coalesce(names, '')); end if;
  return n;
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

-- Only the logged-in person's own applications (status + answers).
create or replace function public.my_applications()
returns table (id uuid, created_at timestamptz, type text, status text, answers jsonb)
language sql stable security definer set search_path = public
as $$
  select a.id, a.created_at, a.type, a.status, a.answers
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

-- Internal helpers: not callable from the website.
revoke all on function public.is_master(text) from public, anon, authenticated;
revoke all on function public.code_hash(text) from public, anon, authenticated;
revoke all on function public.staff_name(text) from public, anon, authenticated;
revoke all on function public.log_action(text, text, text) from public, anon, authenticated;

grant execute on function public.is_staff(text) to anon, authenticated;
grant execute on function public.staff_role(text) to anon, authenticated;
grant execute on function public.staff_login(text) to anon, authenticated;
grant execute on function public.type_is_open(text) to anon, authenticated;
grant execute on function public.get_closed_types() to anon, authenticated;
grant execute on function public.set_type_open(text, text, boolean) to anon, authenticated;
grant execute on function public.list_applications(text) to anon, authenticated;
grant execute on function public.set_application_status(text, text[], text) to anon, authenticated;
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
