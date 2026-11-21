-- BLACK JACK KARAOKE v2 — PostgreSQL / Supabase
create extension if not exists pgcrypto;

create table if not exists events (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 status text not null default 'CLOSED' check(status in ('CLOSED','OPEN','REGISTRATION_CLOSED','FINISHED')),
 capacity integer not null default 45 check(capacity >= 0),
 created_at timestamptz not null default now(),
 opened_at timestamptz,
 closed_at timestamptz
);
create table if not exists dining_tables (
 id text primary key,
 number integer not null unique,
 token text not null unique check(length(token)=32),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
-- Comandas e identidade existem somente dentro de um evento.
create table if not exists event_tabs (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references events(id) on delete cascade,
 tab_number varchar(10) not null,
 participant_name text not null,
 normalized_name text not null,
 created_at timestamptz not null default now(),
 unique(event_id, tab_number)
);
create table if not exists tab_releases (
 event_id uuid not null references events(id) on delete cascade,
 tab_number varchar(10) not null,
 enabled boolean not null default true,
 primary key(event_id, tab_number)
);
create table if not exists presentations (
 id text primary key,
 event_id uuid not null references events(id),
 table_id text not null references dining_tables(id),
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
 unique(event_id, request_id)
);
create index if not exists presentations_event_status_idx on presentations(event_id,status,created_at);
create index if not exists presentations_event_manual_idx on presentations(event_id,manual_rank) where manual_rank is not null;
create table if not exists participants (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references events(id),
 presentation_id text not null references presentations(id) on delete cascade,
 table_id text not null references dining_tables(id),
 name text not null,
 normalized_name text not null,
 created_at timestamptz not null default now()
);
create index if not exists participants_event_name_idx on participants(event_id,table_id,normalized_name);
create table if not exists raffles (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references events(id),
 status text not null default 'RUNNING' check(status in ('RUNNING','FINISHED','CANCELLED')),
 requested_winners integer not null check(requested_winners between 1 and 100),
 created_at timestamptz not null default now(),
 finished_at timestamptz
);
create table if not exists raffle_winners (
 id uuid primary key default gen_random_uuid(),
 raffle_id uuid not null references raffles(id) on delete cascade,
 presentation_id text not null references presentations(id),
 participant_name text not null,
 song text not null,
 table_number integer not null,
 position integer not null,
 unique(raffle_id,participant_name)
);
create table if not exists admins (
 id uuid primary key default gen_random_uuid(),
 display_name text not null,
 role text not null check(role in ('OWNER','ADMIN','COLLABORATOR')),
 password_hash text not null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists audit_logs (
 id bigint generated always as identity primary key,
 event_id uuid references events(id),
 actor text not null default 'system',
 action text not null,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create table if not exists settings (
 key text primary key,
 value jsonb not null
);
-- RLS: clientes nunca recebem acesso direto às tabelas. A API server-side usa service role.
alter table events enable row level security;
alter table dining_tables enable row level security;
alter table event_tabs enable row level security;
alter table tab_releases enable row level security;
alter table presentations enable row level security;
alter table participants enable row level security;
alter table raffles enable row level security;
alter table raffle_winners enable row level security;
alter table admins enable row level security;
alter table audit_logs enable row level security;
alter table settings enable row level security;
-- Sem policies públicas intencionalmente. Service role somente em Netlify Functions.
