# Distinct / Finance

A mobile-first private financial workspace for **Distinct Archives**. Track one Bank location, Cash in hand, personal and freelance transactions, transfers and fixed recurring charges. Installable as a PWA. Built with static HTML/CSS/JavaScript and Supabase Auth + Postgres.

## State of this delivery

**The app and database schema are implemented. Cloud sync is not enabled until you connect your own Supabase project.** The public website starts on a secure-connection setup screen and offers a clearly labeled fictional demo. **Demo entries never save or sync.** Do not enter real finances in Demo mode.

## Enable secure sync (10–20 minutes)

1. Create a private project at [Supabase](https://supabase.com/). Choose a strong Supabase account password and turn on MFA for the admin account.
2. Open your project's **SQL Editor**, paste all of `schema.sql`, and run it. The script creates Bank/Cash accounts, transactions, recurring charges, constraints, indexes, and owner-only Row Level Security (RLS) policies. **Never disable RLS** on these tables.
3. In **Authentication → Providers → Email**, leave email/password sign-in enabled and preferably require email confirmation. For a personal-only app, turn off public signups **after you have created your own user** or use Supabase admin invite flows. Set the permitted redirect/site URL to `https://distinctarchives.github.io/Invoices/finance/` (for hosted deployment).
4. Open **Project Settings → API Keys** (or **Connect → API keys**) and copy the **Project URL** and **publishable** key (`sb_publishable_...`) or legacy **anon** key. **Never use the service_role or sb_secret_ key in client code.**
5. Visit the hosted app at `https://distinctarchives.github.io/Invoices/finance/`, enter the Project URL and publishable key, and sign up with a strong, unique password (10+ characters). Verify your email if required; then sign in.
6. Repeat step 5 on your other device **with the same project URL and key**; sign in with the same account. Both devices then read and write the same private database.
7. If you prefer not to enter the public Project URL and publishable key on each device, configure them in a dedicated public `config.js` in a future deployment. A publishable key is public by design; service-role/secret keys are not.

## Financial rules

- Bank and Cash are **locations**. Account balances = opening balances + income − expenses ± internal transfers.
- A **Bank → Cash** withdrawal reduces Bank and increases Cash equally; it is **never** an expense.
- Each transaction can be tagged **Personal** or **Business**, although both may use the same account.
- TND transactions and balances use **integer millimes** in the database (1 TND = 1000 millimes), avoiding binary floating-point rounding in stored values.
- A fixed charge does not affect balances until you **Mark paid**, which creates an expense with the actual TND amount and your chosen payment location.
- EUR recurring charges store EUR cents + a manually entered **estimated TND equivalent** for forecasts. Confirm your **actual** TND deduction when recording payment. There is no automatic exchange-rate feed.
- For charges due on days 29–31, February and other shorter months use the last day of the month. Yearly charges recur in the calendar month of their start date.
- The dashboard month selector changes monthly income, spending, recurring due, and paid markers. Bank/Cash balances are **current lifetime balances**, not as-of historical month-end balances.
- Activity lists currently load the latest 2,000 transactions per session; add pagination before relying on large volumes.

## Privacy and security boundaries

- GitHub Pages contains only **public app code**, never a copy of your financial database, financial records, or a secret API key.
- Supabase Postgres **RLS** restricts records to the signed-in user. Every transaction also checks both participating account owners. The SQL policy setup is part of security; don't use the frontend with an unprotected or incorrectly configured database.
- Data travels over HTTPS, and Supabase provides encryption at rest as part of its managed service. This implementation is **not end-to-end or zero-knowledge encryption**; authorized backend administrators and the hosting provider may be able to access stored records.
- The browser stores login refresh tokens locally to keep you signed in. Use a secured personal device with a passcode/Face ID, don't share browser profiles, and sign out on a shared computer.
- The UI does not persist financial history in localStorage. The offline cache covers only public app assets. **You need internet access to read or save real entries.**
- CSV exports are **plaintext**, with an explicit warning. The app supports **password-encrypted AES-256-GCM JSON exports** (PBKDF2-SHA256 with 350,000 iterations). **Restoration/import of those encrypted backups is not yet included**; retain cloud data and regular backups. Do not lose the export password.
- The PWA icon may be cached by iOS/Android; remove and re-add the home-screen shortcut after branding changes.

## Deployment

The complete static frontend lives in the repository's `/finance/` directory on the `main` branch. If GitHub Pages is set to **Deploy from a branch → main → /(root)**, this path is served at `https://distinctarchives.github.io/Invoices/finance/`.

No build system, npm dependencies, tracking scripts, or third-party runtime JavaScript. All cloud APIs go to the connected HTTPS Supabase project.

## Planned next additions

- Import previous Excel/CSV records after confirming category mappings and any duplicate handling.
- Savings goals, invoice tracking, spending budgets and scheduled payment reminders.
- Optional MFA enrollment experience and more granular session locking.
- Encrypted-backup restore flow and deeper reconciliation/audit tools.