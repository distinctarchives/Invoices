-- DISTINCT FINANCE · SECURE SUPABASE DATABASE
-- Run in the SQL Editor of your OWN Supabase project.
-- Only the project owner should run this SQL. Safe to rerun in an otherwise unchanged project.
-- All money movements use TND millimes (1 TND = 1,000 millimes).
-- Foreign recurring charges use EUR cents; estimated_tnd_millimes is for forecasts only.

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('bank','cash')),
  opening_balance_millimes bigint not null default 0 check (opening_balance_millimes >= 0 and opening_balance_millimes < 10000000000000),
  created_at timestamptz not null default now(),
  unique(user_id,kind)
);

create table if not exists public.recurring_charges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  category text not null default 'General',
  scope text not null check (scope in ('personal','business')),
  currency text not null check (currency in ('TND','EUR')),
  amount_minor bigint not null check (amount_minor > 0 and amount_minor < 10000000000000),
  estimated_tnd_millimes bigint not null check (estimated_tnd_millimes >= 0 and estimated_tnd_millimes < 10000000000000),
  frequency text not null default 'monthly' check (frequency in ('monthly','yearly')),
  due_day int not null check (due_day between 1 and 31),
  start_date date not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('income','expense','transfer')),
  amount_millimes bigint not null check (amount_millimes > 0 and amount_millimes < 10000000000000),
  account_id uuid not null references public.accounts(id) on delete restrict,
  to_account_id uuid references public.accounts(id) on delete restrict,
  recurring_id uuid references public.recurring_charges(id) on delete restrict,
  period_key text,
  occurred_on date not null,
  description text not null default '' check (char_length(description) <= 140),
  category text not null default 'General',
  scope text not null check (scope in ('personal','business')),
  created_at timestamptz not null default now(),
  check ((kind='transfer' and to_account_id is not null and to_account_id<>account_id and recurring_id is null and period_key is null)
    or (kind in ('income','expense') and to_account_id is null)),
  check ((recurring_id is null and period_key is null) or (kind='expense' and recurring_id is not null and period_key ~ '^\d{4}-(0[1-9]|1[0-2])$'))
);

create unique index if not exists one_recurring_payment_per_period on public.transactions (user_id,recurring_id,period_key) where recurring_id is not null;
create index if not exists tx_owner_date_idx on public.transactions(user_id,occurred_on desc);
create index if not exists recurring_owner_idx on public.recurring_charges(user_id);

alter table public.accounts enable row level security;
alter table public.recurring_charges enable row level security;
alter table public.transactions enable row level security;

-- Prevent accidental open API grants. Permissions still require matching row-level policies.
revoke all on public.accounts, public.recurring_charges, public.transactions from anon;
grant select,insert,update,delete on public.accounts, public.recurring_charges, public.transactions to authenticated;

drop policy if exists accounts_select_own on public.accounts;
create policy accounts_select_own on public.accounts for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists accounts_insert_own on public.accounts;
create policy accounts_insert_own on public.accounts for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists accounts_update_own on public.accounts;
create policy accounts_update_own on public.accounts for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
-- No delete policy on accounts: the Bank and Cash ledgers cannot be removed from the client.

drop policy if exists charges_select_own on public.recurring_charges;
create policy charges_select_own on public.recurring_charges for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists charges_insert_own on public.recurring_charges;
create policy charges_insert_own on public.recurring_charges for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists charges_update_own on public.recurring_charges;
create policy charges_update_own on public.recurring_charges for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
-- Charges are paused instead of deleted, preserving references to historical payments.

-- On read/write, verify not only ownership of the transaction, but also ownership of
-- both participating accounts AND the referenced recurring charge (when applicable).
drop policy if exists transactions_select_own on public.transactions;
create policy transactions_select_own on public.transactions for select to authenticated using (
  user_id = (select auth.uid())
  and exists (select 1 from public.accounts a where a.id = account_id and a.user_id = (select auth.uid()))
  and (to_account_id is null or exists (select 1 from public.accounts a where a.id = to_account_id and a.user_id = (select auth.uid())))
  and (recurring_id is null or exists (select 1 from public.recurring_charges c where c.id = recurring_id and c.user_id = (select auth.uid())))
);
drop policy if exists transactions_insert_own on public.transactions;
create policy transactions_insert_own on public.transactions for insert to authenticated with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.accounts a where a.id = account_id and a.user_id = (select auth.uid()))
  and (to_account_id is null or exists (select 1 from public.accounts a where a.id = to_account_id and a.user_id = (select auth.uid())))
  and (recurring_id is null or exists (select 1 from public.recurring_charges c where c.id = recurring_id and c.user_id = (select auth.uid())))
);
drop policy if exists transactions_delete_own on public.transactions;
create policy transactions_delete_own on public.transactions for delete to authenticated using (
  user_id = (select auth.uid())
  and exists (select 1 from public.accounts a where a.id = account_id and a.user_id = (select auth.uid()))
  and (to_account_id is null or exists (select 1 from public.accounts a where a.id = to_account_id and a.user_id = (select auth.uid())))
);
-- Transactions are immutable: correcting a wrong entry means deleting and recreating it.
-- Row-level security enforces access control, not end-to-end encryption.