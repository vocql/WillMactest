-- Run this ONCE in the Supabase SQL editor (do not commit your real token to GitHub).
-- 1) Replace PASTE_BOT_TOKEN_HERE with your bot token.  2) Run.  3) Refresh the dashboard.
insert into public.bot_secret (id, token) values (1, 'PASTE_BOT_TOKEN_HERE')
on conflict (id) do update set token = excluded.token;

select public.backfill_member_info();   -- fills join date + pfp for everyone who already applied
