-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.
create table if not exists public.game_rooms (
  room_id text primary key,
  distance integer not null default 1330,
  task_index integer not null default 0,
  ready_players text[] not null default '{}',
  history jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.game_rooms enable row level security;

-- Clients cannot read or update this table directly. All access goes through
-- narrowly scoped RPC functions and the unguessable room ID in the invite URL.
create or replace function public.create_game_room()
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare r public.game_rooms;
begin
  insert into public.game_rooms(room_id)
  values (gen_random_uuid()::text)
  returning * into r;
  return to_jsonb(r);
end;
$$;

create or replace function public.get_game_room(p_room_id text)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare r public.game_rooms;
begin
  select * into r from public.game_rooms where room_id = p_room_id;
  if not found then raise exception 'Room not found'; end if;
  return to_jsonb(r);
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
  r public.game_rooms;
  step_reward integer;
begin
  if p_player not in ('dasha', 'lenya') then raise exception 'Invalid player'; end if;
  select * into r from public.game_rooms where room_id = p_room_id for update;
  if not found then raise exception 'Room not found'; end if;

  -- Repeated taps from the same player are idempotent. Distance only changes
  -- when the other player has already confirmed this task.
  if p_player = any(r.ready_players) then return to_jsonb(r); end if;

  if cardinality(r.ready_players) > 0 then
    step_reward := least(greatest(coalesce(p_reward, 0), 0), r.distance);
    update public.game_rooms
       set distance = greatest(0, distance - step_reward),
           task_index = task_index + 1,
           ready_players = '{}',
           history = history || jsonb_build_array(
             jsonb_build_object('m', step_reward, 't', left(coalesce(p_task, ''), 300))
           ),
           updated_at = now()
     where room_id = p_room_id
     returning * into r;
  else
    update public.game_rooms
       set ready_players = array[p_player], updated_at = now()
     where room_id = p_room_id
     returning * into r;
  end if;
  return to_jsonb(r);
end;
$$;

revoke all on function public.create_game_room() from public;
revoke all on function public.get_game_room(text) from public;
revoke all on function public.confirm_game_step(text, text, integer, text) from public;
grant execute on function public.create_game_room() to anon, authenticated;
grant execute on function public.get_game_room(text) to anon, authenticated;
grant execute on function public.confirm_game_step(text, text, integer, text) to anon, authenticated;
