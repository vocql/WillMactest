# Will Mac | Mod Applications

A static site for **GitHub Pages**. Applicants fill in a one-screen, step-by-step form (no page scrolling).
Every application is saved and shown on a staff dashboard at `/applications/`.

    willmac-mod-apps/
    ├── index.html               the application page (step-by-step wizard)
    ├── applications/index.html  staff dashboard, at yoursite/applications/
    ├── config.js                everything you edit: keys, webhook, questions, requirements, staff, FAQ
    ├── supabase.sql             database setup (also holds the staff username)
    └── .nojekyll

## Step 1: Put it on GitHub Pages

1. Create a GitHub repo and upload all the files, keeping the `applications` folder.
2. Repo **Settings > Pages**: Source = Deploy from a branch, Branch = `main`, folder = `/ (root)`, Save.
3. Live at `https://YOUR-USERNAME.github.io/REPO-NAME/`. The dashboard is at `.../REPO-NAME/applications/`.

## Step 2: Saving applications (free Supabase database)

1. Sign up at supabase.com and create a project (free plan is fine).
2. Open **SQL Editor > New query**, paste everything from `supabase.sql`, press **Run**.
   (If you ran an older version of this file before, run this one too. It upgrades it.)
3. Open **Project Settings > API**. Copy the **Project URL** and the **anon / publishable key**.
4. In `config.js`, paste them into `supabaseUrl` and `supabaseKey`, commit.

## Application types (Moderator, Creator, Event Host, Partnership)

The application page now opens on a picker. Each type has its own questions, requirements and confirm text, all in
`window.WM_CONFIG.types` at the bottom of `config.js`. The Moderator type still uses the original `questions`.
Direct links: `/?type=mod`, `/?type=creator`, `/?type=events`, `/?type=partner`.
To add a type, copy a block (the first question must always be the Discord name). `open: false` closes just that type.
Set `discordWebhook` inside a type to send it to its own Discord channel.

**If you already set Supabase up, run the new `supabase.sql` again.** It adds the `type` column and a new staff login.
The dashboard will not work until you do. The dashboard has a type filter and shows the type on every application.

## Application progress bar

Applicants see a progress bar for each application under **My applications**, with a status message, the reviewer's
name, an optional message from staff, and a "Progress history" list. Staff control it from the dashboard
(reviewer and admin roles only): open an application, pick a status, optionally set the reviewer and a message,
and press **Save progress**. "I'll review this" claims it in one click. You can also select several applications
and use **Set status** to change them together.

| Status | Bar |
| --- | --- |
| Submitted | 25% |
| Being reviewed / Needs more info / On hold | 50% |
| Interview | 75% |
| Approved / Denied (red) | 100% |

**You must run the new `supabase.sql` once** (SQL Editor > New query > paste > Run). It adds the new statuses,
the reviewer / message columns, the history table and the functions the dashboard calls. Until you do, "Save progress"
shows an error. It is safe to run again. While an application is in any open status (everything except
Approved / Denied), the same person can't send another one of the same type.

## Staff login

Open `/applications/` and type the username **macstaff**. No password.

The username is checked by the database, not by the website, so it isn't visible in your page source and
nobody can read applications without it. To change it, edit `'macstaff'` (it appears once) in `supabase.sql` and run
the file again. Keep in mind it works like a shared password: anyone you tell it to can read applications, and it
isn't rate limited, so pick something hard to guess if the applications are sensitive.

## Step 3: Discord alerts (optional)

Channel settings > Integrations > Webhooks > New Webhook > Copy URL, paste into `discordWebhook` in `config.js`.
Each new application posts an embed. Discord messages show the full answers, so keep that channel staff-only.

## Optional: copy to Google Form

Form > three dots > Get pre-filled link, fill every question, Get link, and copy each `entry.123456789` from the
URL (in question order) into `googleForm.entries`. Check the Responses tab after a test.

## Dashboard

Search, sort, read full answers, copy, export CSV, auto-refreshes every 30 seconds. Unread applications have a
dot. There are no accept / deny buttons; it's read-only.

## Closing applications

Easiest: log in to `/applications/`, press **Open / close**, and click the switch for any type. It takes effect
immediately and is enforced by the database too (needs the latest `supabase.sql`).
In `config.js`: `applicationsOpen: false` closes everything, `open: false` on a type closes just that one.

## Good to know

- `config.js` is public. The Supabase key in it only allows submitting applications; reading needs the staff
  username. A determined person could still submit junk applications. If that happens, regenerate the key.
- Discord webhook URLs in `config.js` are public too. If the channel gets spammed, delete the webhook and make a new one.

## Icons

Each type has a white icon (`WM_CONFIG.icons` in `config.js`). To use your own, add `icon: "https://link-to-image"` to a type.
The image is turned white automatically.

## Troubleshooting Supabase

The pages now show the real error. "HTTP 404" means `supabase.sql` wasn't run (or run it again). "401/403" means the
URL/key don't match the project. "Failed to fetch" usually means the Supabase project is paused (free projects pause
after about a week idle: open the Supabase dashboard and click Restore) or the URL is wrong.
