-- DISTINCT / TIME V2 — Run once in the SQL Editor of the SAME Supabase
-- project used by Distinct Finance. Does not modify Finance tables.
-- All records belong to auth.uid(); service-role credentials must NEVER enter frontend.

create table if not exists public.work_time_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 100),
  created_at timestamptz not null default now(),
  unique(user_id, name)
);

create table if not exists public.work_time_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project text not null check (char_length(btrim(project)) between 1 and 100),
  task text not null default 'Design work' check (char_length(btrim(task)) between 1 and 200),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_ms bigint not null check (duration_ms > 0 and duration_ms <= 86400000),
  segments jsonb not null default '[]'::jsonb check (jsonb_typeof(segments) = 'array'),
  source text not null default 'manual' check (source in ('timer','manual','import','corrected')),
  legacy_id text check (legacy_id is null or char_length(legacy_id) between 1 and 150),
  created_at timestamptz not null default now(),
  check (ended_at > started_at),
  unique(user_id, legacy_id)
);
create index if not exists work_time_entries_user_start on public.work_time_entries(user_id, started_at desc);

create table if not exists public.work_time_active (
  user_id uuid primary key references auth.users(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  project text not null check (char_length(btrim(project)) between 1 and 100),
  task text not null check (char_length(btrim(task)) between 1 and 200),
  started_at timestamptz not null,
  running_since timestamptz,
  accrued_ms bigint not null default 0 check (accrued_ms >= 0),
  segments jsonb not null default '[]'::jsonb check (jsonb_typeof(segments) = 'array'),
  updated_at timestamptz not null default now()
);

alter table public.work_time_projects enable row level security;
alter table public.work_time_entries enable row level security;
alter table public.work_time_active enable row level security;

revoke all on public.work_time_projects, public.work_time_entries, public.work_time_active from anon;
grant select, insert, update, delete on public.work_time_projects, public.work_time_entries to authenticated;
grant select on public.work_time_active to authenticated;
-- Timer state changes can only be made using the atomic RPC below.
revoke insert, update, delete on public.work_time_active from authenticated;

-- Projects
drop policy if exists "time_projects_select" on public.work_time_projects;
create policy "time_projects_select" on public.work_time_projects for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "time_projects_insert" on public.work_time_projects;
create policy "time_projects_insert" on public.work_time_projects for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "time_projects_update" on public.work_time_projects;
create policy "time_projects_update" on public.work_time_projects for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "time_projects_delete" on public.work_time_projects;
create policy "time_projects_delete" on public.work_time_projects for delete to authenticated using (user_id = (select auth.uid()));
-- Time entries
drop policy if exists "time_entries_select" on public.work_time_entries;
create policy "time_entries_select" on public.work_time_entries for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "time_entries_insert" on public.work_time_entries;
create policy "time_entries_insert" on public.work_time_entries for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "time_entries_update" on public.work_time_entries;
create policy "time_entries_update" on public.work_time_entries for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "time_entries_delete" on public.work_time_entries;
create policy "time_entries_delete" on public.work_time_entries for delete to authenticated using (user_id = (select auth.uid()));
-- Active timer (read-only except through action RPC)
drop policy if exists "time_active_select" on public.work_time_active;
create policy "time_active_select" on public.work_time_active for select to authenticated using (user_id = (select auth.uid()));

-- Atomic, server-clock timer actions. One timer per signed-in user; works across devices.
create or replace function public.work_time_timer_action(
  p_action text,
  p_project text default null,
  p_task text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  who uuid := (select auth.uid());
  a public.work_time_active%rowtype;
  t timestamptz;
  add_ms bigint;
  total_ms bigint;
  final_segments jsonb;
begin
  if who is null then raise exception 'You must sign in first'; end if;
  if p_action not in ('start','pause','resume','finish','discard') then raise exception 'Invalid timer action'; end if;
  -- Prevent two devices starting or finishing simultaneously.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(who::text, 8155));
  t := pg_catalog.clock_timestamp();
  select * into a from public.work_time_active where user_id=who for update;

  if p_action='start' then
    if found then raise exception 'A timer is already active on another device. Refresh.'; end if;
    if p_project is null or char_length(btrim(p_project)) not between 1 and 100 then raise exception 'Choose a project'; end if;
    if p_task is null or char_length(btrim(p_task)) not between 1 and 200 then raise exception 'Enter a task'; end if;
    insert into public.work_time_active(user_id, project, task, started_at, running_since)
    values (who, btrim(p_project), btrim(p_task), t, t);

  elsif p_action='pause' then
    if not found or a.running_since is null then raise exception 'Timer is not running. Refresh.'; end if;
    add_ms := greatest(0, round(extract(epoch from (t-a.running_since))*1000)::bigint);
    update public.work_time_active
    set accrued_ms=a.accrued_ms+add_ms, running_since=null,
        segments=a.segments || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'start',round(extract(epoch from a.running_since)*1000)::bigint,
          'end',round(extract(epoch from t)*1000)::bigint)),
        updated_at=t
    where user_id=who;

  elsif p_action='resume' then
    if not found or a.running_since is not null then raise exception 'Timer is not paused. Refresh.'; end if;
    update public.work_time_active set running_since=t, updated_at=t where user_id=who;

  elsif p_action='discard' then
    if not found then raise exception 'No active timer'; end if;
    delete from public.work_time_active where user_id=who;

  elsif p_action='finish' then
    if not found then raise exception 'No active timer. Refresh.'; end if;
    add_ms := case when a.running_since is not null
      then greatest(0, round(extract(epoch from (t-a.running_since))*1000)::bigint)
      else 0 end;
    total_ms := a.accrued_ms+add_ms;
    if total_ms < 1000 then raise exception 'Session is too short; discard instead'; end if;
    if total_ms > 86400000 then raise exception 'Timer exceeds 24h; contact support to split the session'; end if;
    final_segments := a.segments;
    if a.running_since is not null then
      final_segments:=final_segments || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'start',round(extract(epoch from a.running_since)*1000)::bigint,
        'end',round(extract(epoch from t)*1000)::bigint));
    end if;
    insert into public.work_time_entries(id, user_id, project, task, started_at, ended_at, duration_ms, segments, source)
    values(a.id, who, a.project, a.task, a.started_at, t, total_ms, final_segments, 'timer');
    delete from public.work_time_active where user_id=who;
  end if;
  return pg_catalog.jsonb_build_object('ok',true,'action',p_action);
end;
$$;
revoke all on function public.work_time_timer_action(text,text,text) from public, anon;
grant execute on function public.work_time_timer_action(text,text,text) to authenticated;

-- Ask PostgREST to notice newly created tables/functions.
notify pgrst, 'reload schema';
