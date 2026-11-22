-- BLACK JACK KARAOKE V2 — TRANSMISSÃO, FILA E HISTÓRICO
-- Migração incremental e idempotente. Não apaga nem recria dados existentes.

begin;

alter table public.presentations
  add column if not exists hide_on_screen boolean not null default false;

create table if not exists public.screen_sessions (
  event_id uuid primary key references public.events(id) on delete cascade,
  session_id text not null,
  active boolean not null default false,
  started_by text,
  updated_at timestamptz not null default now(),
  expires_at timestamptz
);
alter table public.screen_sessions enable row level security;

-- START libera a apresentação para aparecer no telão, inclusive quando foi
-- criada manualmente e estava oculta até o início.
create or replace function public.bj_presentation_action(
  p_action text,p_presentation_id text,p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_p public.presentations%rowtype; v_status text;
begin
  select * into v_p from public.presentations where id=p_presentation_id for update;
  if not found then raise exception 'Apresentação não encontrada.'; end if;
  perform 1 from public.events where id=v_p.event_id for update;
  if p_action='START' then
    if v_p.status not in ('PENDING','PLAYING') then raise exception 'Esta apresentação não está aguardando.'; end if;
    if exists(select 1 from public.presentations where event_id=v_p.event_id and status='PLAYING' and id<>v_p.id) then raise exception 'Já existe uma apresentação tocando agora.'; end if;
    update public.presentations set status='PLAYING',started_at=coalesce(started_at,now()),hide_on_screen=false,updated_at=now() where id=v_p.id returning status into v_status;
  elsif p_action='SUNG' then
    if v_p.status not in ('PENDING','PLAYING') then raise exception 'Esta apresentação não pode ser marcada como cantada.'; end if;
    update public.presentations set status='SUNG',sung_at=now(),updated_at=now() where id=v_p.id returning status into v_status;
    insert into public.participant_stats(event_id,table_id,normalized_name,name,songs_sung,last_sung_at)
      select v_p.event_id,pt.table_id,pt.normalized_name,pt.name,1,now() from public.participants pt where pt.presentation_id=v_p.id
      on conflict(event_id,table_id,normalized_name) do update set songs_sung=public.participant_stats.songs_sung+1,last_sung_at=excluded.last_sung_at,name=excluded.name;
    insert into public.queue_state(event_id,last_sung_table_number,updated_at) values(v_p.event_id,v_p.table_number,now())
      on conflict(event_id) do update set last_sung_table_number=excluded.last_sung_table_number,updated_at=now();
  elsif p_action='CANCEL' then
    if v_p.status not in ('PENDING','PLAYING') then raise exception 'Somente apresentações aguardando podem ser canceladas.'; end if;
    update public.presentations set status='CANCELLED',cancelled_at=now(),updated_at=now() where id=v_p.id returning status into v_status;
  else raise exception 'Ação de apresentação inválida.'; end if;
  insert into public.audit_logs(event_id,actor,action,details)
    values(v_p.event_id,coalesce(p_actor,'admin'),'PRESENTATION_'||p_action,
      jsonb_build_object('presentation_id',v_p.id,'table',v_p.table_number,'tab',v_p.tab_number));
  return jsonb_build_object('ok',true,'id',v_p.id,'status',v_status);
end $$;

create or replace function public.bj_admin_add_presentation(
  p_event_id uuid,p_table_id text,p_tab text,p_p1 text,p_p2 text,p_p3 text,p_song text,p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_event public.events%rowtype;
  v_table public.dining_tables%rowtype;
  v_tab text:=upper(trim(coalesce(p_tab,'')));
  v_p1 text:=trim(coalesce(p_p1,''));
  v_p2 text:=nullif(trim(coalesce(p_p2,'')),'');
  v_p3 text:=nullif(trim(coalesce(p_p3,'')),'');
  v_song text:=trim(coalesce(p_song,''));
  v_old public.event_tabs%rowtype;
  v_id text;
  v_names text[];
  v_norms text[];
begin
  if v_tab !~ '^[A-Z0-9]{1,10}$' then raise exception 'Comanda inválida. Use letras e números, até 10 caracteres.'; end if;
  if length(v_p1)<2 or length(v_p1)>70 then raise exception 'Informe o nome do participante principal.'; end if;
  if (v_p2 is not null and length(v_p2)>70) or (v_p3 is not null and length(v_p3)>70) then raise exception 'Nome de participante muito longo.'; end if;
  if length(v_song)<2 or length(v_song)>150 then raise exception 'Informe o nome da música (2 a 150 caracteres).'; end if;

  v_names:=array[v_p1]||case when v_p2 is null then array[]::text[] else array[v_p2] end||case when v_p3 is null then array[]::text[] else array[v_p3] end;
  v_norms:=array(select public.bj_norm(x) from unnest(v_names) x);
  if (select count(distinct x) from unnest(v_norms) x)<>cardinality(v_norms) then raise exception 'Não repita participantes na mesma apresentação.'; end if;

  select * into v_event from public.events where id=p_event_id for update;
  if not found or v_event.status='FINISHED' then raise exception 'A noite selecionada não está disponível.'; end if;
  select * into v_table from public.dining_tables where id=p_table_id and active=true;
  if not found then raise exception 'Selecione uma mesa ativa.'; end if;

  select * into v_old from public.event_tabs where event_id=v_event.id and tab_number=v_tab for update;
  if found then
    if v_old.normalized_name<>public.bj_norm(v_p1) then
      raise exception 'O nome informado não corresponde ao cadastro desta comanda.';
    end if;
  else
    insert into public.event_tabs(event_id,tab_number,participant_name,normalized_name)
      values(v_event.id,v_tab,v_p1,public.bj_norm(v_p1));
  end if;

  if exists(select 1 from public.presentations where event_id=v_event.id and tab_number=v_tab and status in ('PENDING','PLAYING')) then
    raise exception 'Esta comanda já possui uma apresentação aguardando ou tocando.';
  end if;

  insert into public.tab_releases(event_id,tab_number,enabled)
    values(v_event.id,v_tab,true)
    on conflict(event_id,tab_number) do update set enabled=true;

  v_id:='M-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  update public.events set capacity=capacity+1 where id=v_event.id;
  insert into public.presentations(
    id,event_id,table_id,table_number,tab_number,p1,p2,p3,song,status,request_id,hide_on_screen
  ) values(
    v_id,v_event.id,v_table.id,v_table.number,v_tab,v_p1,v_p2,v_p3,v_song,'PENDING',
    'MANUAL-'||replace(gen_random_uuid()::text,'-',''),true
  );
  insert into public.participants(event_id,presentation_id,table_id,name,normalized_name)
    select v_event.id,v_id,v_table.id,x,public.bj_norm(x) from unnest(v_names) x;
  insert into public.queue_state(event_id) values(v_event.id) on conflict(event_id) do nothing;
  insert into public.audit_logs(event_id,actor,action,details)
    values(v_event.id,coalesce(p_actor,'admin'),'MANUAL_PRESENTATION_ADDED',
      jsonb_build_object('presentation_id',v_id,'table',v_table.number,'tab',v_tab,'song',v_song,'capacity_increased',1));
  return jsonb_build_object('ok',true,'id',v_id,'table_number',v_table.number,'tab_number',v_tab,'capacity_increased',1,'hidden_on_screen_until_started',true);
end $$;

create or replace function public.bj_restore_sung_presentation(
  p_presentation_id text,p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_p public.presentations%rowtype; v_result jsonb;
begin
  select * into v_p from public.presentations where id=p_presentation_id for update;
  if not found then raise exception 'Apresentação não encontrada.'; end if;
  if v_p.status<>'SUNG' then raise exception 'Somente músicas já cantadas podem voltar para a fila.'; end if;
  perform 1 from public.events where id=v_p.event_id for update;
  if exists(
    select 1 from public.presentations
    where event_id=v_p.event_id and tab_number=v_p.tab_number
      and status in ('PENDING','PLAYING') and id<>v_p.id
  ) then raise exception 'Esta comanda já possui outra música aguardando ou tocando. Conclua ou cancele essa música antes de devolver a anterior.'; end if;

  update public.participant_stats ps
    set songs_sung=greatest(0,ps.songs_sung-1),
        last_sung_at=(
          select max(pr.sung_at)
          from public.participants pt
          join public.presentations pr on pr.id=pt.presentation_id
          where pr.event_id=v_p.event_id and pr.status='SUNG'
            and pt.table_id=ps.table_id and pt.normalized_name=ps.normalized_name
            and pr.id<>v_p.id
        )
    from public.participants pt
    where pt.presentation_id=v_p.id and ps.event_id=v_p.event_id
      and ps.table_id=pt.table_id and ps.normalized_name=pt.normalized_name;
  delete from public.participant_stats ps
    using public.participants pt
    where pt.presentation_id=v_p.id and ps.event_id=v_p.event_id
      and ps.table_id=pt.table_id and ps.normalized_name=pt.normalized_name
      and ps.songs_sung<=0;

  update public.presentations
    set status='PENDING',sung_at=null,started_at=null,manual_position=null,manual_rank=null,
        hide_on_screen=false,updated_at=now()
    where id=v_p.id;

  select public.bj_queue_pin_position(v_p.event_id,v_p.id,4,p_actor) into v_result;
  insert into public.audit_logs(event_id,actor,action,details)
    values(v_p.event_id,coalesce(p_actor,'admin'),'PRESENTATION_RESTORED_TO_QUEUE',
      jsonb_build_object('presentation_id',v_p.id,'default_position',4));
  return jsonb_build_object('ok',true,'id',v_p.id,'status','PENDING','position',coalesce((v_result->>'position')::integer,4));
end $$;

revoke all on function public.bj_admin_add_presentation(uuid,text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.bj_restore_sung_presentation(text,text) from public,anon,authenticated;
grant execute on function public.bj_admin_add_presentation(uuid,text,text,text,text,text,text,text) to service_role;
grant execute on function public.bj_restore_sung_presentation(text,text) to service_role;

commit;
