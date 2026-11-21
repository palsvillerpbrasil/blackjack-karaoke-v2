-- BLACK JACK KARAOKE V2 — PERFIL COLABORADOR E CONTROLE DE LANÇAMENTO DO HISTÓRICO
-- Migração incremental e idempotente. Não apaga nem recria dados existentes.

begin;

alter table public.participants
  add column if not exists external_registered_at timestamptz,
  add column if not exists external_registered_by text;

create index if not exists participants_external_registered_idx
  on public.participants(event_id, external_registered_at)
  where external_registered_at is not null;

-- Garante que cada integrante das apresentações já cantadas tenha seu próprio registro
-- para que a marcação seja individual, inclusive em apresentações antigas/importadas.
insert into public.participants(event_id, presentation_id, table_id, name, normalized_name)
select p.event_id, p.id, p.table_id, person.name, public.bj_norm(person.name)
from public.presentations p
cross join lateral (values (p.p1), (p.p2), (p.p3)) as person(name)
where p.status = 'SUNG'
  and nullif(trim(person.name), '') is not null
  and not exists (
    select 1
    from public.participants existing
    where existing.presentation_id = p.id
      and existing.normalized_name = public.bj_norm(person.name)
  );

commit;
