# Distinct / Time — Cloud Edition (V2)

A separate, opt-in upgrade of the [original time tracker](https://distinctarchives.github.io/Invoices/time/). The legacy app remains accessible and **none of its local data is changed** by this release.

**New link:** https://distinctarchives.github.io/Invoices/time/v2/

## Key improvements

- **Add hours manually** from the timer screen or history: project, task, start and end time. Edit and delete recorded sessions.
- **One timer per account**: start on phone, pause or finish on desktop. Server-controlled start/pause/resume/finish operations prevent conflicting writes.
- **Private cloud history**: projects and sessions stored in the same Supabase project as Distinct Finance, with owner-only RLS policies.
- **Existing data migration**: import old local data or a JSON backup; repeated imports ignore duplicate legacy session IDs. Original data is never deleted automatically.
- **Mobile-first/PWA**: install from Safari/Chrome, use Distinct branding, export CSV and JSON.

## Setup (requires one manual action by project owner)

1. Go to your **existing Distinct Finance Supabase project** → SQL Editor.
2. Copy and run the entire contents of [`schema.sql`](./schema.sql). This creates `work_time_projects`, `work_time_entries`, and `work_time_active`, plus RLS and the atomic `work_time_timer_action` function. It **does not affect Finance tables**.
3. Open https://distinctarchives.github.io/Invoices/time/v2/ . On the same browser and domain as Distinct Finance, the app can read its saved public Supabase project URL and publishable key; otherwise enter those values manually. Never use your secret or service-role key.
4. **Sign in with the same email/password as Distinct Finance** (both connect to the same Supabase project). Your time data is separate from your financial data.
5. Under **Settings**, choose **Import hours from this device**. If the previous app was installed separately on iOS and its browser storage is isolated, open the old app first, export a JSON backup, then use **Import old JSON backup** in V2.
6. Repeat step 4 on your computer. Existing cloud sessions will appear automatically; the display updates when you save an entry, refresh, return to the app, or during the ~20-second foreground sync.

**Important migration note:** If your old local timer is still running, finish it in the legacy app before importing. Old unfinished timers are not automatically migrated. The old app remains available at `/Invoices/time/`.

## Security and privacy

- This is public frontend code on GitHub Pages; actual work sessions are **only** in your Supabase database (except optional downloaded backups and original legacy local data).
- The RLS policies restrict all three tables to the signed-in account. The timer RPC verifies `auth.uid()` and locks per-user timer operations.
- The URL and `sb_publishable_…` key are intended to be public. **Never** publish a service-role key or database password.
- Sessions use HTTPS and a browser-stored refresh token. Lock your devices; sign out on shared devices. Like Distinct Finance, data is not end-to-end encrypted.
- The installed PWA caches only application assets; **real edits need internet access**.
- CSV and JSON exports are **not encrypted**. Save them only in private storage. The app does not yet provide automatic backups or restore of cloud-format JSON.
- Manual session edits replace the corrected session's recorded work segment with the selected start–end period. For paused sessions, do not correct them unless the whole period was worked.
- Time-tracking entries are restricted to 24 hours per session. Avoid leaving the timer running overnight; a long-running timer can be discarded and its correct hours entered manually.

## No automatic migration

The previous version's localStorage key is `distinct.time-tracker.v1`. It is read for optional import and **never deleted** or overwritten by V2. This release is published separately to avoid disrupting an active legacy timer.
