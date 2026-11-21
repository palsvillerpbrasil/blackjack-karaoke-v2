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
