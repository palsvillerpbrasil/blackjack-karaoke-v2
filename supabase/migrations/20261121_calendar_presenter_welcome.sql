-- BLACK JACK KARAOKE V2 — CALENDARIO DE EVENTOS E APRESENTADOR
-- Migração incremental e idempotente. Não apaga nem altera registros existentes.
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

alter table public.karaoke_calendar add column if not exists presenter_name text;
alter table public.karaoke_calendar add column if not exists has_karaoke boolean not null default true;
alter table public.karaoke_calendar add column if not exists created_by text;
alter table public.karaoke_calendar add column if not exists created_at timestamptz not null default now();
alter table public.karaoke_calendar add column if not exists updated_at timestamptz not null default now();
create index if not exists karaoke_calendar_event_date_idx on public.karaoke_calendar(event_date) where has_karaoke = true;
alter table public.karaoke_calendar enable row level security;
