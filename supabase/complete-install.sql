-- INSTALACAO COMPLETA: execute este arquivo somente em um projeto Supabase novo.
-- No projeto BLACK JACK existente, execute apenas migrations/20261121_complete_system.sql.
-- BLACK JACK KARAOKE V2 — ESQUEMA BASE SUPABASE
-- Para instalação nova. No projeto existente, execute somente a migração incremental.
create extension if not exists pgcrypto;

create table if not exists public.events (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 status text not null default 'CLOSED' check(status in ('CLOSED','OPEN','REGISTRATION_CLOSED','FINISHED')),
 capacity integer not null default 45 check(capacity >= 0),
 created_at timestamptz not null default now(),
 opened_at timestamptz,
 closed_at timestamptz
);
create table if not exists public.karaoke_calendar (
 id uuid primary key default gen_random_uuid(),
 event_date date not null unique,
 title text,
 presenter_name text,
 has_karaoke boolean not null default true,
 created_by text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.dining_tables (
 id text primary key,
 number integer not null unique,
 token text not null unique check(length(token)=32),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.event_tabs (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.events(id) on delete cascade,
 tab_number varchar(10) not null,
 participant_name text not null,
 normalized_name text not null,
 created_at timestamptz not null default now(),
 unique(event_id,tab_number)
);
create table if not exists public.tab_releases (
 event_id uuid not null references public.events(id) on delete cascade,
 tab_number varchar(10) not null,
 enabled boolean not null default true,
 primary key(event_id,tab_number)
);
create table if not exists public.presentations (
 id text primary key,
 event_id uuid not null references public.events(id),
 table_id text not null references public.dining_tables(id),
 table_number integer not null,
 tab_number varchar(10) not null,
 p1 text not null, p2 text, p3 text,
 song text not null,
 youtube_url text,
 status text not null default 'PENDING' check(status in ('PENDING','PLAYING','SUNG','CANCELLED')),
 request_id text not null,
 manual_position integer,
 manual_rank bigint,
 created_at timestamptz not null default now(),
 started_at timestamptz,
 sung_at timestamptz,
 cancelled_at timestamptz,
 unique(event_id,request_id)
);
create index if not exists presentations_event_status_idx on public.presentations(event_id,status,created_at);
create index if not exists presentations_event_manual_idx on public.presentations(event_id,manual_rank) where manual_rank is not null;
create table if not exists public.participants (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.events(id),
 presentation_id text not null references public.presentations(id) on delete cascade,
 table_id text not null references public.dining_tables(id),
 name text not null,
 normalized_name text not null,
 created_at timestamptz not null default now()
);
create index if not exists participants_event_name_idx on public.participants(event_id,table_id,normalized_name);
create table if not exists public.raffles (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.events(id),
 status text not null default 'RUNNING' check(status in ('RUNNING','FINISHED','CANCELLED')),
 requested_winners integer not null check(requested_winners between 1 and 100),
 created_at timestamptz not null default now(),
 finished_at timestamptz
);
create table if not exists public.raffle_winners (
 id uuid primary key default gen_random_uuid(),
 raffle_id uuid not null references public.raffles(id) on delete cascade,
 presentation_id text not null references public.presentations(id),
 participant_name text not null,
 song text not null,
 table_number integer not null,
 position integer not null,
 unique(raffle_id,participant_name)
);
create table if not exists public.admins (
 id uuid primary key default gen_random_uuid(),
 display_name text not null,
 role text not null check(role in ('OWNER','ADMIN','COLLABORATOR')),
 password_hash text not null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
 id bigint generated always as identity primary key,
 event_id uuid references public.events(id),
 actor text not null default 'system',
 action text not null,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create table if not exists public.settings (
 key text primary key,
 value jsonb not null
);

alter table public.events enable row level security;
alter table public.dining_tables enable row level security;
alter table public.event_tabs enable row level security;
alter table public.tab_releases enable row level security;
alter table public.presentations enable row level security;
alter table public.participants enable row level security;
alter table public.raffles enable row level security;
alter table public.raffle_winners enable row level security;
alter table public.admins enable row level security;
alter table public.audit_logs enable row level security;
alter table public.settings enable row level security;
-- Sem políticas públicas. O backend usa service_role exclusivamente na Netlify Function.


-- MIGRACAO COMPLETA
-- BLACK JACK KARAOKE V2 — MIGRACAO COMPLETA
-- Incremental e idempotente. Nao apaga dados existentes.
create extension if not exists pgcrypto;

alter table public.presentations add column if not exists round_number integer;
alter table public.presentations add column if not exists manual_position integer;
alter table public.presentations add column if not exists manual_rank bigint;
alter table public.presentations add column if not exists updated_at timestamptz not null default now();
alter table public.presentations alter column tab_number drop not null;
alter table public.events add column if not exists legacy_id text;
alter table public.audit_logs add column if not exists legacy_id text;
alter table public.raffles add column if not exists reveal_at timestamptz;
alter table public.raffles add column if not exists results_ready boolean not null default false;
alter table public.raffle_winners add column if not exists event_id uuid references public.events(id);
alter table public.raffle_winners add column if not exists participant_norm text;
alter table public.raffle_winners add column if not exists created_at timestamptz not null default now();

update public.raffle_winners rw
set event_id = r.event_id,
    participant_norm = translate(lower(regexp_replace(trim(rw.participant_name), '\s+', ' ', 'g')),'áàãâäéèêëíìîïóòõôöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')
from public.raffles r, public.presentations p
where rw.raffle_id = r.id and rw.presentation_id = p.id and rw.event_id is null;

create table if not exists public.participant_stats (
  event_id uuid not null references public.events(id) on delete cascade,
  table_id text not null references public.dining_tables(id),
  normalized_name text not null,
  name text not null,
  songs_sung integer not null default 0,
  last_sung_at timestamptz,
  primary key(event_id,table_id,normalized_name)
);
create table if not exists public.admin_login_limits (
  ip_hash text primary key,
  attempts integer not null default 0,
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz,
  updated_at timestamptz not null default now()
);
create table if not exists public.queue_state (
  event_id uuid primary key references public.events(id) on delete cascade,
  last_sung_table_number integer,
  manual_mode boolean not null default false,
  updated_at timestamptz not null default now()
);
create index if not exists presentations_event_status_created_idx on public.presentations(event_id,status,created_at);
create index if not exists presentations_event_manual_rank_idx on public.presentations(event_id,manual_rank) where manual_rank is not null;
create index if not exists participants_event_norm_idx on public.participants(event_id,normalized_name);
create index if not exists participant_stats_event_norm_idx on public.participant_stats(event_id,normalized_name);
create unique index if not exists events_legacy_id_unique_idx on public.events(legacy_id);
create unique index if not exists audit_logs_legacy_id_unique_idx on public.audit_logs(legacy_id);
do $$ begin
  if not exists(select 1 from public.participants group by presentation_id,normalized_name having count(*)>1) then
    create unique index if not exists participants_presentation_norm_unique_idx on public.participants(presentation_id,normalized_name);
  end if;
end $$;
create index if not exists raffle_winners_event_norm_idx on public.raffle_winners(event_id,participant_norm);

-- Indices unicos sao criados somente se os dados legados ja respeitam a regra.
do $$ begin
  if not exists (select 1 from public.presentations where status in ('PENDING','PLAYING') group by event_id,tab_number having count(*)>1) then
    create unique index if not exists presentations_one_pending_per_tab_idx on public.presentations(event_id,tab_number) where status in ('PENDING','PLAYING');
  end if;
  if not exists (select 1 from public.raffle_winners where event_id is not null and participant_norm is not null group by event_id,participant_norm having count(*)>1) then
    create unique index if not exists raffle_winners_once_per_event_idx on public.raffle_winners(event_id,participant_norm) where event_id is not null and participant_norm is not null;
  end if;
end $$;

alter table public.queue_state enable row level security;
alter table public.admin_login_limits enable row level security;
alter table public.participant_stats enable row level security;
insert into public.queue_state(event_id) select id from public.events on conflict(event_id) do nothing;

create or replace function public.bj_norm(p_value text) returns text
language sql immutable set search_path=public,pg_temp as $$
  select translate(lower(regexp_replace(trim(coalesce(p_value,'')), '\s+', ' ', 'g')),'áàãâäéèêëíìîïóòõôöúùûüçñ','aaaaaeeeeiiiiooooouuuucn');
$$;

create or replace function public.bj_login_guard(p_ip_hash text,p_success boolean)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.admin_login_limits%rowtype; v_now timestamptz:=now(); v_attempts integer;
begin
  insert into public.admin_login_limits(ip_hash) values(p_ip_hash) on conflict(ip_hash) do nothing;
  select * into v from public.admin_login_limits where ip_hash=p_ip_hash for update;
  if p_success is null then
    return jsonb_build_object('allowed',v.blocked_until is null or v.blocked_until<=v_now,'blocked_until',v.blocked_until,'attempts',v.attempts);
  elsif p_success then
    update public.admin_login_limits set attempts=0,window_started_at=v_now,blocked_until=null,updated_at=v_now where ip_hash=p_ip_hash;
    return jsonb_build_object('allowed',true,'attempts',0);
  end if;
  if v.blocked_until is not null and v.blocked_until>v_now then
    return jsonb_build_object('allowed',false,'blocked_until',v.blocked_until,'attempts',v.attempts);
  end if;
  v_attempts:=case when v.window_started_at<v_now-interval '15 minutes' then 1 else v.attempts+1 end;
  update public.admin_login_limits set attempts=v_attempts,window_started_at=case when v.window_started_at<v_now-interval '15 minutes' then v_now else v.window_started_at end,
    blocked_until=case when v_attempts>=8 then v_now+interval '15 minutes' else null end,updated_at=v_now where ip_hash=p_ip_hash;
  return jsonb_build_object('allowed',v_attempts<8,'attempts',v_attempts,'blocked_until',case when v_attempts>=8 then v_now+interval '15 minutes' else null end);
end $$;

create or replace function public.bj_identify_tab(p_token text,p_tab text,p_name text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_event public.events%rowtype; v_table public.dining_tables%rowtype; v_existing public.event_tabs%rowtype; v_tab text:=upper(trim(coalesce(p_tab,''))); v_name text:=trim(coalesce(p_name,'')); v_pending boolean;
begin
  if v_tab !~ '^[A-Z0-9]{1,10}$' then raise exception 'Informe uma comanda válida (até 10 caracteres).'; end if;
  if length(v_name)<2 or length(v_name)>70 then raise exception 'Informe seu nome (2 a 70 caracteres).'; end if;
  select * into v_event from public.events order by created_at desc limit 1 for update;
  if not found or v_event.status='FINISHED' then raise exception 'Não existe evento aberto para inscrições.'; end if;
  if v_event.status<>'OPEN' then raise exception 'As inscrições estão fechadas.'; end if;
  select * into v_table from public.dining_tables where token=lower(p_token) and active=true;
  if not found then raise exception 'Mesa inválida ou desativada.'; end if;
  if not exists(select 1 from public.tab_releases where event_id=v_event.id and tab_number=v_tab and enabled=true) then raise exception 'Sua comanda não está liberada. Consulte os responsáveis.'; end if;
  select * into v_existing from public.event_tabs where event_id=v_event.id and tab_number=v_tab;
  if found then
    if v_existing.normalized_name<>public.bj_norm(v_name) then raise exception 'Esta comanda já está cadastrada com outro nome. Procure um responsável.'; end if;
  else
    insert into public.event_tabs(event_id,tab_number,participant_name,normalized_name) values(v_event.id,v_tab,v_name,public.bj_norm(v_name));
  end if;
  select exists(select 1 from public.presentations where event_id=v_event.id and tab_number=v_tab and status in ('PENDING','PLAYING')) into v_pending;
  return jsonb_build_object('ok',true,'event_id',v_event.id,'name',v_name,'pending',v_pending,'can_submit',not v_pending,'table_number',v_table.number);
end $$;

create or replace function public.bj_register_presentation(p_token text,p_tab text,p_p1 text,p_p2 text,p_p3 text,p_song text,p_request_id text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_event public.events%rowtype; v_table public.dining_tables%rowtype; v_tab text:=upper(trim(coalesce(p_tab,'')));
  v_p1 text:=trim(coalesce(p_p1,'')); v_p2 text:=nullif(trim(coalesce(p_p2,'')),''); v_p3 text:=nullif(trim(coalesce(p_p3,'')),'');
  v_song text:=trim(coalesce(p_song,'')); v_old public.event_tabs%rowtype; v_id text; v_used integer; v_names text[]; v_norms text[];
begin
  if v_tab !~ '^[A-Z0-9]{1,10}$' then raise exception 'Informe uma comanda válida (até 10 caracteres).'; end if;
  if length(v_p1)<2 or length(v_p1)>70 then raise exception 'Informe o nome do participante principal.'; end if;
  if (v_p2 is not null and length(v_p2)>70) or (v_p3 is not null and length(v_p3)>70) then raise exception 'Nome de participante muito longo.'; end if;
  if length(v_song)<2 or length(v_song)>150 then raise exception 'Informe o nome da música (2 a 150 caracteres).'; end if;
  if coalesce(trim(p_request_id),'')='' then raise exception 'Identificador da solicitação ausente.'; end if;
  v_names:=array[v_p1]||case when v_p2 is null then array[]::text[] else array[v_p2] end||case when v_p3 is null then array[]::text[] else array[v_p3] end;
  v_norms:=array(select public.bj_norm(x) from unnest(v_names) x);
  if (select count(distinct x) from unnest(v_norms) x)<>cardinality(v_norms) then raise exception 'Não repita participantes na mesma apresentação.'; end if;
  select * into v_event from public.events order by created_at desc limit 1 for update;
  if not found or v_event.status<>'OPEN' then raise exception 'Inscrições fechadas.'; end if;
  select * into v_table from public.dining_tables where token=lower(p_token) and active=true;
  if not found then raise exception 'Mesa inválida ou desativada.'; end if;
  if not exists(select 1 from public.tab_releases where event_id=v_event.id and tab_number=v_tab and enabled=true) then raise exception 'Sua comanda não está liberada. Consulte os responsáveis.'; end if;
  select id into v_id from public.presentations where event_id=v_event.id and request_id=p_request_id limit 1;
  if found then return jsonb_build_object('ok',true,'id',v_id,'duplicate',true); end if;
  select * into v_old from public.event_tabs where event_id=v_event.id and tab_number=v_tab;
  if not found then insert into public.event_tabs(event_id,tab_number,participant_name,normalized_name) values(v_event.id,v_tab,v_p1,public.bj_norm(v_p1));
  elsif v_old.normalized_name<>public.bj_norm(v_p1) then raise exception 'O nome não corresponde ao cadastro desta comanda.'; end if;
  if exists(select 1 from public.presentations where event_id=v_event.id and tab_number=v_tab and status in ('PENDING','PLAYING')) then raise exception 'Esta comanda já possui uma apresentação aguardando. Aguarde ela ser cantada ou cancelada.'; end if;
  select count(*) into v_used from public.presentations where event_id=v_event.id and status in ('PENDING','PLAYING','SUNG');
  if v_used>=v_event.capacity then raise exception 'Capacidade da noite esgotada.'; end if;
  v_id:='A-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  insert into public.presentations(id,event_id,table_id,table_number,tab_number,p1,p2,p3,song,status,request_id)
  values(v_id,v_event.id,v_table.id,v_table.number,v_tab,v_p1,v_p2,v_p3,v_song,'PENDING',p_request_id);
  insert into public.participants(event_id,presentation_id,table_id,name,normalized_name)
  select v_event.id,v_id,v_table.id,x,public.bj_norm(x) from unnest(v_names) x;
  insert into public.audit_logs(event_id,actor,action,details) values(v_event.id,'cliente','RESERVA',jsonb_build_object('presentation_id',v_id,'table',v_table.number,'song',v_song));
  insert into public.queue_state(event_id) values(v_event.id) on conflict(event_id) do nothing;
  return jsonb_build_object('ok',true,'id',v_id,'table_number',v_table.number);
end $$;

create or replace function public.bj_presentation_action(p_action text,p_presentation_id text,p_actor text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_p public.presentations%rowtype; v_status text;
begin
  select * into v_p from public.presentations where id=p_presentation_id for update;
  if not found then raise exception 'Apresentação não encontrada.'; end if;
  perform 1 from public.events where id=v_p.event_id for update;
  if p_action='START' then
    if v_p.status not in ('PENDING','PLAYING') then raise exception 'Esta apresentação não está aguardando.'; end if;
    if exists(select 1 from public.presentations where event_id=v_p.event_id and status='PLAYING' and id<>v_p.id) then raise exception 'Já existe uma apresentação tocando agora.'; end if;
    update public.presentations set status='PLAYING',started_at=coalesce(started_at,now()),updated_at=now() where id=v_p.id returning status into v_status;
  elsif p_action='SUNG' then
    if v_p.status not in ('PENDING','PLAYING') then raise exception 'Esta apresentação não pode ser marcada como cantada.'; end if;
    update public.presentations set status='SUNG',sung_at=now(),updated_at=now() where id=v_p.id returning status into v_status;
    insert into public.participant_stats(event_id,table_id,normalized_name,name,songs_sung,last_sung_at)
      select v_p.event_id,pt.table_id,pt.normalized_name,pt.name,1,now() from public.participants pt where pt.presentation_id=v_p.id
      on conflict(event_id,table_id,normalized_name) do update set songs_sung=public.participant_stats.songs_sung+1,last_sung_at=excluded.last_sung_at,name=excluded.name;
    insert into public.queue_state(event_id,last_sung_table_number,updated_at) values(v_p.event_id,v_p.table_number,now()) on conflict(event_id) do update set last_sung_table_number=excluded.last_sung_table_number,updated_at=now();
  elsif p_action='CANCEL' then
    if v_p.status not in ('PENDING','PLAYING') then raise exception 'Somente apresentações aguardando podem ser canceladas.'; end if;
    update public.presentations set status='CANCELLED',cancelled_at=now(),updated_at=now() where id=v_p.id returning status into v_status;
  else raise exception 'Ação de apresentação inválida.'; end if;
  insert into public.audit_logs(event_id,actor,action,details) values(v_p.event_id,coalesce(p_actor,'admin'),'PRESENTATION_'||p_action,jsonb_build_object('presentation_id',v_p.id,'table',v_p.table_number,'tab',v_p.tab_number));
  return jsonb_build_object('ok',true,'id',v_p.id,'status',v_status);
end $$;

create or replace function public.bj_queue_reorder(p_event_id uuid,p_ids text[],p_actor text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer; v_valid integer;
begin
  perform 1 from public.events where id=p_event_id for update; if not found then raise exception 'Evento não encontrado.'; end if;
  select count(*) into v_count from public.presentations where event_id=p_event_id and status='PENDING';
  if cardinality(coalesce(p_ids,array[]::text[]))<>v_count then raise exception 'A lista enviada não corresponde à fila atual. Atualize o painel.'; end if;
  select count(*) into v_valid from public.presentations where event_id=p_event_id and status='PENDING' and id=any(p_ids);
  if v_valid<>v_count then raise exception 'A fila contém apresentações inválidas ou repetidas.'; end if;
  update public.presentations p set manual_rank=x.ord*1000,manual_position=x.ord,updated_at=now() from unnest(p_ids) with ordinality as x(id,ord) where p.id=x.id and p.event_id=p_event_id;
  insert into public.queue_state(event_id,manual_mode,updated_at) values(p_event_id,true,now()) on conflict(event_id) do update set manual_mode=true,updated_at=now();
  insert into public.audit_logs(actor,action,details) values(coalesce(p_actor,'admin'),'QUEUE_REORDERED',jsonb_build_object('event_id',p_event_id,'count',v_count));
  return jsonb_build_object('ok',true,'count',v_count);
end $$;

create or replace function public.bj_queue_auto(p_event_id uuid,p_actor text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform 1 from public.events where id=p_event_id for update; if not found then raise exception 'Evento não encontrado.'; end if;
  update public.presentations set manual_rank=null,manual_position=null,updated_at=now() where event_id=p_event_id and status='PENDING';
  insert into public.queue_state(event_id,manual_mode,updated_at) values(p_event_id,false,now()) on conflict(event_id) do update set manual_mode=false,updated_at=now();
  insert into public.audit_logs(actor,action,details) values(coalesce(p_actor,'admin'),'QUEUE_AUTO_RESTORED',jsonb_build_object('event_id',p_event_id));
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.bj_edit_presentation(
  p_presentation_id text,p_p1 text,p_p2 text,p_p3 text,p_song text,p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_p public.presentations%rowtype; v_names text[]; v_norms text[]; v_p2 text:=nullif(trim(coalesce(p_p2,'')),''); v_p3 text:=nullif(trim(coalesce(p_p3,'')),'');
begin
  select * into v_p from public.presentations where id=p_presentation_id for update;
  if not found then raise exception 'Apresentação não encontrada.'; end if;
  if v_p.status not in ('PENDING','PLAYING') then raise exception 'Somente apresentações aguardando podem ser editadas.'; end if;
  if length(trim(coalesce(p_p1,'')))<2 or length(trim(p_p1))>70 then raise exception 'Nome do participante principal inválido.'; end if;
  if length(trim(coalesce(p_song,'')))<2 or length(trim(p_song))>150 then raise exception 'Nome da música inválido.'; end if;
  v_names:=array[trim(p_p1)]||case when v_p2 is null then array[]::text[] else array[v_p2] end||case when v_p3 is null then array[]::text[] else array[v_p3] end;
  v_norms:=array(select public.bj_norm(x) from unnest(v_names) x);
  if (select count(distinct x) from unnest(v_norms) x)<>cardinality(v_norms) then raise exception 'Não repita participantes.'; end if;
  perform 1 from public.events where id=v_p.event_id for update;
  update public.presentations set p1=trim(p_p1),p2=v_p2,p3=v_p3,song=trim(p_song),updated_at=now() where id=v_p.id;
  delete from public.participants where presentation_id=v_p.id;
  insert into public.participants(event_id,presentation_id,table_id,name,normalized_name)
    select v_p.event_id,v_p.id,v_p.table_id,x,public.bj_norm(x) from unnest(v_names) x;
  update public.event_tabs set participant_name=trim(p_p1),normalized_name=public.bj_norm(p_p1)
    where event_id=v_p.event_id and tab_number=v_p.tab_number;
  insert into public.audit_logs(event_id,actor,action,details)
    values(v_p.event_id,coalesce(p_actor,'admin'),'PRESENTATION_EDITED',jsonb_build_object('presentation_id',v_p.id,'song',trim(p_song)));
  return jsonb_build_object('ok',true,'id',v_p.id);
end $$;

create or replace function public.bj_save_raffle_winners(p_raffle_id uuid,p_event_id uuid,p_winners jsonb,p_actor text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_r public.raffles%rowtype; v_item jsonb; v_name text; v_norm text; v_count integer:=0;
begin
  perform 1 from public.events where id=p_event_id for update;
  select * into v_r from public.raffles where id=p_raffle_id and event_id=p_event_id for update;
  if not found then raise exception 'Sorteio não encontrado.'; end if;
  if v_r.status<>'RUNNING' or v_r.results_ready then raise exception 'Este sorteio já foi processado.'; end if;
  if exists(select 1 from public.raffles where event_id=p_event_id and status='RUNNING' and id<>p_raffle_id) then raise exception 'Já existe um sorteio em andamento.'; end if;
  for v_item in select value from jsonb_array_elements(p_winners) loop
    v_name:=trim(coalesce(v_item->>'participant_name','')); v_norm:=coalesce(v_item->>'participant_norm',public.bj_norm(v_name));
    if v_name='' or v_norm='' then raise exception 'Vencedor inválido.'; end if;
    if exists(select 1 from public.raffle_winners where event_id=p_event_id and participant_norm=v_norm) then raise exception 'Uma pessoa selecionada já ganhou neste evento.'; end if;
    if exists(select 1 from public.raffle_winners where raffle_id=p_raffle_id and participant_norm=v_norm) then raise exception 'O sorteio contém nomes repetidos.'; end if;
    if not exists(select 1 from public.participants pt join public.presentations pr on pr.id=pt.presentation_id where pr.event_id=p_event_id and pr.status='SUNG' and pt.presentation_id=v_item->>'presentation_id' and pt.normalized_name=v_norm) then raise exception 'Participante não elegível para o sorteio.'; end if;
    insert into public.raffle_winners(raffle_id,event_id,presentation_id,participant_name,participant_norm,song,table_number,position)
    values(p_raffle_id,p_event_id,v_item->>'presentation_id',v_name,v_norm,v_item->>'song',(v_item->>'table_number')::integer,(v_item->>'position')::integer);
    v_count:=v_count+1;
  end loop;
  if v_count<>v_r.requested_winners then raise exception 'Quantidade de vencedores diferente da solicitada.'; end if;
  update public.raffles set results_ready=true,reveal_at=now()+interval '8 seconds' where id=p_raffle_id;
  insert into public.audit_logs(event_id,actor,action,details) values(p_event_id,coalesce(p_actor,'admin'),'RAFFLE_DRAWN',jsonb_build_object('raffle_id',p_raffle_id,'winners',v_count));
  return jsonb_build_object('ok',true,'raffle_id',p_raffle_id,'winners',v_count,'reveal_at',now()+interval '8 seconds');
end $$;

revoke all on function public.bj_norm(text) from public,anon,authenticated;
revoke all on function public.bj_login_guard(text,boolean) from public,anon,authenticated;
revoke all on function public.bj_identify_tab(text,text,text) from public,anon,authenticated;
revoke all on function public.bj_register_presentation(text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.bj_presentation_action(text,text,text) from public,anon,authenticated;
revoke all on function public.bj_queue_reorder(uuid,text[],text) from public,anon,authenticated;
revoke all on function public.bj_queue_auto(uuid,text) from public,anon,authenticated;
revoke all on function public.bj_edit_presentation(text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.bj_save_raffle_winners(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.bj_norm(text) to service_role;
grant execute on function public.bj_login_guard(text,boolean) to service_role;
grant execute on function public.bj_identify_tab(text,text,text) to service_role;
grant execute on function public.bj_register_presentation(text,text,text,text,text,text,text) to service_role;
grant execute on function public.bj_presentation_action(text,text,text) to service_role;
grant execute on function public.bj_queue_reorder(uuid,text[],text) to service_role;
grant execute on function public.bj_queue_auto(uuid,text) to service_role;
grant execute on function public.bj_edit_presentation(text,text,text,text,text,text) to service_role;
grant execute on function public.bj_save_raffle_winners(uuid,uuid,jsonb,text) to service_role;


-- BLACK JACK KARAOKE V2 — AJUSTES DE FILA, COMANDAS E HISTÓRICO
-- Migração incremental: não apaga nem recria dados existentes.

-- Converte prioridades antigas que tenham somente manual_rank para posições explícitas.
update public.presentations
set manual_position=greatest(1,round(manual_rank/1000.0)::integer)
where manual_position is null and manual_rank is not null and status='PENDING';


create or replace function public.bj_queue_pin_position(
  p_event_id uuid, p_presentation_id text, p_position integer, p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer; v_old_position integer; v_target integer;
begin
  perform 1 from public.events where id=p_event_id for update;
  if not found then raise exception 'Evento não encontrado.'; end if;
  select count(*) into v_count from public.presentations where event_id=p_event_id and status='PENDING';
  if v_count=0 then raise exception 'Não há apresentações aguardando.'; end if;
  select manual_position into v_old_position from public.presentations
    where id=p_presentation_id and event_id=p_event_id and status='PENDING' for update;
  if not found then raise exception 'Apresentação não encontrada na fila.'; end if;
  if p_position is null or p_position<1 then raise exception 'Informe uma posição válida.'; end if;
  v_target:=least(p_position,v_count);

  if v_old_position is null then
    update public.presentations set manual_position=manual_position+1,manual_rank=(manual_position+1)*1000,updated_at=now()
      where event_id=p_event_id and status='PENDING' and id<>p_presentation_id and manual_position is not null and manual_position>=v_target;
  elsif v_old_position<v_target then
    update public.presentations set manual_position=manual_position-1,manual_rank=(manual_position-1)*1000,updated_at=now()
      where event_id=p_event_id and status='PENDING' and id<>p_presentation_id and manual_position>v_old_position and manual_position<=v_target;
  elsif v_old_position>v_target then
    update public.presentations set manual_position=manual_position+1,manual_rank=(manual_position+1)*1000,updated_at=now()
      where event_id=p_event_id and status='PENDING' and id<>p_presentation_id and manual_position>=v_target and manual_position<v_old_position;
  end if;

  update public.presentations set manual_position=v_target,manual_rank=v_target*1000,updated_at=now()
    where id=p_presentation_id and event_id=p_event_id and status='PENDING';
  insert into public.queue_state(event_id,manual_mode,updated_at) values(p_event_id,true,now())
    on conflict(event_id) do update set manual_mode=true,updated_at=now();
  insert into public.audit_logs(actor,action,details) values(coalesce(p_actor,'admin'),'QUEUE_ITEM_PINNED',
    jsonb_build_object('event_id',p_event_id,'presentation_id',p_presentation_id,'position',v_target));
  return jsonb_build_object('ok',true,'presentation_id',p_presentation_id,'position',v_target,'manual_adjustments_preserved',true);
end $$;

create or replace function public.bj_queue_unpin_position(
  p_event_id uuid, p_presentation_id text, p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_old_position integer;
begin
  perform 1 from public.events where id=p_event_id for update;
  if not found then raise exception 'Evento não encontrado.'; end if;
  select manual_position into v_old_position from public.presentations
    where id=p_presentation_id and event_id=p_event_id and status='PENDING' for update;
  if not found then raise exception 'Apresentação não encontrada na fila.'; end if;
  if v_old_position is null then return jsonb_build_object('ok',true,'unchanged',true); end if;
  update public.presentations set manual_position=manual_position-1,manual_rank=(manual_position-1)*1000,updated_at=now()
    where event_id=p_event_id and status='PENDING' and id<>p_presentation_id and manual_position>v_old_position;
  update public.presentations set manual_position=null,manual_rank=null,updated_at=now()
    where id=p_presentation_id and event_id=p_event_id and status='PENDING';
  insert into public.audit_logs(actor,action,details) values(coalesce(p_actor,'admin'),'QUEUE_ITEM_UNPINNED',
    jsonb_build_object('event_id',p_event_id,'presentation_id',p_presentation_id));
  return jsonb_build_object('ok',true,'presentation_id',p_presentation_id,'automatic',true);
end $$;

-- O automático permanece ativo para toda a fila; os itens ajustados manualmente
-- continuam como exceções pontuais e não são apagados por este comando.
create or replace function public.bj_queue_auto(p_event_id uuid,p_actor text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_preserved integer;
begin
  perform 1 from public.events where id=p_event_id for update;
  if not found then raise exception 'Evento não encontrado.'; end if;
  select count(*) into v_preserved from public.presentations where event_id=p_event_id and status='PENDING' and manual_position is not null;
  insert into public.queue_state(event_id,manual_mode,updated_at) values(p_event_id,false,now())
    on conflict(event_id) do update set manual_mode=false,updated_at=now();
  insert into public.audit_logs(actor,action,details) values(coalesce(p_actor,'admin'),'QUEUE_AUTO_RESTORED',
    jsonb_build_object('event_id',p_event_id,'manual_positions_preserved',v_preserved));
  return jsonb_build_object('ok',true,'manual_positions_preserved',v_preserved,'automatic_active',true);
end $$;

create or replace function public.bj_admin_update_tab(
  p_event_id uuid, p_old_tab text, p_new_tab text, p_name text, p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_old public.event_tabs%rowtype;
  v_old_tab text:=upper(trim(coalesce(p_old_tab,'')));
  v_new_tab text:=upper(trim(coalesce(p_new_tab,'')));
  v_name text:=trim(coalesce(p_name,''));
  v_new_norm text;
  v_presentations_updated integer:=0;
begin
  if v_old_tab !~ '^[A-Z0-9]{1,10}$' or v_new_tab !~ '^[A-Z0-9]{1,10}$' then
    raise exception 'Comanda inválida. Use letras e números, até 10 caracteres.';
  end if;
  if length(v_name)<2 or length(v_name)>70 then raise exception 'O nome deve ter entre 2 e 70 caracteres.'; end if;
  v_new_norm:=public.bj_norm(v_name);
  perform 1 from public.events where id=p_event_id for update;
  if not found then raise exception 'Evento não encontrado.'; end if;
  select * into v_old from public.event_tabs where event_id=p_event_id and tab_number=v_old_tab for update;
  if not found then raise exception 'Comanda cadastrada não encontrada.'; end if;

  if v_new_tab<>v_old_tab then
    if exists(select 1 from public.event_tabs where event_id=p_event_id and tab_number=v_new_tab) then
      raise exception 'A nova comanda já está vinculada a outra pessoa.';
    end if;
    if not exists(select 1 from public.tab_releases where event_id=p_event_id and tab_number=v_new_tab and enabled=true) then
      raise exception 'Libere a nova comanda antes de fazer a troca.';
    end if;
    if exists(select 1 from public.presentations where event_id=p_event_id and tab_number=v_new_tab and status in ('PENDING','PLAYING')) then
      raise exception 'A nova comanda já possui uma apresentação aguardando ou tocando.';
    end if;
  end if;

  if v_old.normalized_name<>v_new_norm then
    update public.participants pt set name=v_name,normalized_name=v_new_norm
      from public.presentations pr
      where pt.presentation_id=pr.id and pr.event_id=p_event_id and pr.tab_number=v_old_tab
        and public.bj_norm(pr.p1)=v_old.normalized_name and pt.normalized_name=v_old.normalized_name;
    update public.presentations set p1=v_name,updated_at=now()
      where event_id=p_event_id and tab_number=v_old_tab and public.bj_norm(p1)=v_old.normalized_name;
    -- participant_stats é agregado por nome/mesa. Só movemos o agregado
    -- quando nenhuma outra comanda da noite usa o mesmo nome antigo.
    if not exists(select 1 from public.event_tabs where event_id=p_event_id and tab_number<>v_old_tab and normalized_name=v_old.normalized_name) then
      insert into public.participant_stats(event_id,table_id,normalized_name,name,songs_sung,last_sung_at)
        select event_id,table_id,v_new_norm,v_name,songs_sung,last_sung_at from public.participant_stats
        where event_id=p_event_id and normalized_name=v_old.normalized_name
        on conflict(event_id,table_id,normalized_name) do update set
          songs_sung=public.participant_stats.songs_sung+excluded.songs_sung,
          last_sung_at=greatest(public.participant_stats.last_sung_at,excluded.last_sung_at),name=excluded.name;
      delete from public.participant_stats where event_id=p_event_id and normalized_name=v_old.normalized_name;
    end if;
  else
    update public.presentations set p1=v_name,updated_at=now()
      where event_id=p_event_id and tab_number=v_old_tab and public.bj_norm(p1)=v_old.normalized_name;
    update public.participants pt set name=v_name
      from public.presentations pr
      where pt.presentation_id=pr.id and pr.event_id=p_event_id and pr.tab_number=v_old_tab
        and public.bj_norm(pr.p1)=v_old.normalized_name and pt.normalized_name=v_old.normalized_name;
    update public.participant_stats set name=v_name where event_id=p_event_id and normalized_name=v_old.normalized_name;
  end if;

  update public.presentations set tab_number=v_new_tab,updated_at=now()
    where event_id=p_event_id and tab_number=v_old_tab;
  get diagnostics v_presentations_updated=row_count;
  update public.event_tabs set tab_number=v_new_tab,participant_name=v_name,normalized_name=v_new_norm
    where event_id=p_event_id and tab_number=v_old_tab;
  insert into public.audit_logs(event_id,actor,action,details)
    values(p_event_id,coalesce(p_actor,'admin'),'TAB_IDENTITY_UPDATED',jsonb_build_object(
      'old_tab',v_old_tab,'new_tab',v_new_tab,'old_name',v_old.participant_name,'new_name',v_name,'presentations_updated',v_presentations_updated));
  return jsonb_build_object('ok',true,'old_tab',v_old_tab,'tab',v_new_tab,'name',v_name,'presentations_updated',v_presentations_updated);
end $$;


-- Editar uma apresentação individual não altera a identidade global da comanda.
-- Correções globais de nome/comanda são feitas por bj_admin_update_tab.
create or replace function public.bj_edit_presentation(
  p_presentation_id text,p_p1 text,p_p2 text,p_p3 text,p_song text,p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_p public.presentations%rowtype; v_names text[]; v_norms text[]; v_p2 text:=nullif(trim(coalesce(p_p2,'')),''); v_p3 text:=nullif(trim(coalesce(p_p3,'')),'');
begin
  select * into v_p from public.presentations where id=p_presentation_id for update;
  if not found then raise exception 'Apresentação não encontrada.'; end if;
  if v_p.status not in ('PENDING','PLAYING') then raise exception 'Somente apresentações aguardando podem ser editadas.'; end if;
  if length(trim(coalesce(p_p1,'')))<2 or length(trim(p_p1))>70 then raise exception 'Nome do participante principal inválido.'; end if;
  if length(trim(coalesce(p_song,'')))<2 or length(trim(p_song))>150 then raise exception 'Nome da música inválido.'; end if;
  v_names:=array[trim(p_p1)]||case when v_p2 is null then array[]::text[] else array[v_p2] end||case when v_p3 is null then array[]::text[] else array[v_p3] end;
  v_norms:=array(select public.bj_norm(x) from unnest(v_names) x);
  if (select count(distinct x) from unnest(v_norms) x)<>cardinality(v_norms) then raise exception 'Não repita participantes.'; end if;
  perform 1 from public.events where id=v_p.event_id for update;
  update public.presentations set p1=trim(p_p1),p2=v_p2,p3=v_p3,song=trim(p_song),updated_at=now() where id=v_p.id;
  delete from public.participants where presentation_id=v_p.id;
  insert into public.participants(event_id,presentation_id,table_id,name,normalized_name)
    select v_p.event_id,v_p.id,v_p.table_id,x,public.bj_norm(x) from unnest(v_names) x;
  insert into public.audit_logs(event_id,actor,action,details)
    values(v_p.event_id,coalesce(p_actor,'admin'),'PRESENTATION_EDITED',jsonb_build_object('presentation_id',v_p.id,'song',trim(p_song)));
  return jsonb_build_object('ok',true,'id',v_p.id);
end $$;

revoke all on function public.bj_queue_pin_position(uuid,text,integer,text) from public,anon,authenticated;
revoke all on function public.bj_queue_unpin_position(uuid,text,text) from public,anon,authenticated;
revoke all on function public.bj_admin_update_tab(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.bj_queue_pin_position(uuid,text,integer,text) to service_role;
grant execute on function public.bj_queue_unpin_position(uuid,text,text) to service_role;
grant execute on function public.bj_admin_update_tab(uuid,text,text,text,text) to service_role;
