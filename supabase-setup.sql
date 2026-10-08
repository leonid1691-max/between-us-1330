-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.
create table if not exists public.game_rooms (
  room_id text primary key,
  distance integer not null default 1330,
  task_index integer not null default 0,
  ready_players text[] not null default '{}',
  history jsonb not null default '[]'::jsonb,
  start_date date not null default date '2026-10-08',
  target_date date not null default date '2026-10-24',
  updated_at timestamptz not null default now()
);

-- Also upgrades rooms created with an earlier version of this game.
alter table public.game_rooms add column if not exists start_date date not null default date '2026-10-08';
alter table public.game_rooms add column if not exists target_date date not null default date '2026-10-24';
alter table public.game_rooms enable row level security;

-- Clients cannot read or update this table directly. All access goes through
-- narrowly scoped RPC functions and the unguessable room ID in the invite URL.
create or replace function public.create_game_room()
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  room_row public.game_rooms%rowtype;
  today_in_moscow date;
  new_room_id text;
begin
  today_in_moscow := (now() at time zone 'Europe/Moscow')::date;
  if today_in_moscow > date '2026-10-24' then raise exception 'The arrival date has passed'; end if;
  new_room_id := gen_random_uuid()::text;
  insert into public.game_rooms(room_id, start_date, target_date)
  values (new_room_id, today_in_moscow, date '2026-10-24');
  select * into room_row from public.game_rooms where room_id = new_room_id;
  return to_jsonb(room_row);
end;
$$;

create or replace function public.get_game_room(p_room_id text)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  room_row public.game_rooms%rowtype;
begin
  select * into room_row from public.game_rooms where room_id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  return to_jsonb(room_row);
end;
$$;

create or replace function public.confirm_game_step(
  p_room_id text,
  p_player text,
  p_reward integer,
  p_task text
)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  room_row public.game_rooms%rowtype;
  step_reward integer;
  today_in_moscow date;
  v_days_elapsed integer;
  v_unlocked integer;
  v_total_steps integer;
begin
  if p_player not in ('dasha', 'lenya') then raise exception 'Invalid player'; end if;
  select * into room_row from public.game_rooms where room_id = p_room_id for update;
  if not found then raise exception 'Room not found'; end if;
  today_in_moscow := (now() at time zone 'Europe/Moscow')::date;
  v_days_elapsed := greatest(0, least(room_row.target_date - room_row.start_date + 1, today_in_moscow - room_row.start_date + 1));
  v_unlocked := v_days_elapsed * 3;
  v_total_steps := greatest(3, (room_row.target_date - room_row.start_date + 1) * 3);
  if room_row.task_index >= v_unlocked then raise exception 'Three tasks for today are already complete'; end if;

  -- Repeated taps from the same player are idempotent. Distance only changes
  -- when the other player has already confirmed this task.
  if p_player = any(room_row.ready_players) then return to_jsonb(room_row); end if;

  if cardinality(room_row.ready_players) > 0 then
    -- Split all 1330 metres evenly over the available three-a-day task slots.
    -- The first remainder slots receive one extra metre; the final slot lands at zero.
    step_reward := (1330 / v_total_steps) + case when room_row.task_index < (1330 % v_total_steps) then 1 else 0 end;
    step_reward := least(step_reward, room_row.distance);
    update public.game_rooms
       set distance = greatest(0, distance - step_reward),
           task_index = task_index + 1,
           ready_players = '{}',
           history = history || jsonb_build_array(
             jsonb_build_object('m', step_reward, 't', left(coalesce(p_task, ''), 300))
           ),
           updated_at = now()
     where room_id = p_room_id;
    select * into room_row from public.game_rooms where room_id = p_room_id;
  else
    update public.game_rooms
       set ready_players = array[p_player], updated_at = now()
     where room_id = p_room_id;
    select * into room_row from public.game_rooms where room_id = p_room_id;
  end if;
  return to_jsonb(room_row);
end;
$$;

revoke all on function public.create_game_room() from public;
revoke all on function public.get_game_room(text) from public;
revoke all on function public.confirm_game_step(text, text, integer, text) from public;
grant execute on function public.create_game_room() to anon, authenticated;
grant execute on function public.get_game_room(text) to anon, authenticated;
grant execute on function public.confirm_game_step(text, text, integer, text) to anon, authenticated;
