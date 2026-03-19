-- ============================================================
-- AmoCRM: таблица для хранения токенов
-- Запустить в Supabase SQL Editor
-- ============================================================

create table if not exists amocrm_tokens (
  id          int primary key default 1,           -- всегда одна строка
  access_token  text not null,
  refresh_token text not null,
  expires_at    bigint not null,                   -- unix timestamp (секунды)
  updated_at    timestamptz default now()
);

-- Ограничение: только одна строка
alter table amocrm_tokens
  add constraint amocrm_tokens_single_row check (id = 1);

-- Доступ только через service_role (Edge Functions), не через anon
alter table amocrm_tokens enable row level security;

-- Нет публичных политик — только service_role имеет доступ
