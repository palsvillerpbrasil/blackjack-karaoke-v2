-- BLACK JACK KARAOKE V2 — HORARIO DOS EVENTOS PROGRAMADOS
-- Incremental e idempotente: mantém as datas e os apresentadores existentes.
alter table public.karaoke_calendar
  add column if not exists start_time time not null default '19:00';

update public.karaoke_calendar
set start_time = '19:00'
where start_time is null;
