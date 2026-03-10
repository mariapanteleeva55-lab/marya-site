-- ============================================================
-- МАРЬЯ — Реферальная система + Аналитика
-- Запустить в Supabase → SQL Editor
-- ============================================================


-- ------------------------------------------------------------
-- 1. РЕФЕРАЛЬНЫЕ КОДЫ
--    Один уникальный код на пользователя
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS referral_codes (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  code       text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ------------------------------------------------------------
-- 2. СВЯЗИ РЕФЕРЕР → РЕФЕРАЛ
--    referee_id UNIQUE — у каждого пользователя только один реферер
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS referrals (
  id          bigserial PRIMARY KEY,
  referrer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referee_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz DEFAULT now(),
  UNIQUE(referee_id)
);

-- ------------------------------------------------------------
-- 3. ПАРТНЁРСКИЙ СЧЁТ
--    balance              — текущий баланс к выплате (рубли)
--    total_earned         — всего заработано за всё время
--    total_referrals_spent — суммарные покупки всех рефералов
--    tier                 — 'base' (5%) или 'premium' (10%)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS partner_accounts (
  user_id                uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance                numeric DEFAULT 0,
  total_earned           numeric DEFAULT 0,
  total_referrals_spent  numeric DEFAULT 0,
  tier                   text DEFAULT 'base' CHECK (tier IN ('base', 'premium')),
  updated_at             timestamptz DEFAULT now()
);

-- ------------------------------------------------------------
-- 4. ИСТОРИЯ РЕФЕРАЛЬНЫХ ВОЗНАГРАЖДЕНИЙ
--    status: 'pending' → начислено, 'paid' → выплачено
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS referral_rewards (
  id           bigserial PRIMARY KEY,
  referrer_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referee_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id     text NOT NULL,
  order_amount numeric NOT NULL,
  reward_rate  numeric NOT NULL,   -- 0.05 или 0.10
  reward_amount numeric NOT NULL,
  status       text DEFAULT 'pending' CHECK (status IN ('pending', 'paid')),
  created_at   timestamptz DEFAULT now()
);

-- ------------------------------------------------------------
-- 5. АНАЛИТИКА — СОБЫТИЯ
--    Трекинг ключевых действий для дашборда
--    event_type: 'pageview' | 'add_to_cart' | 'purchase' | 'registration' | 'ref_link_view'
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics_events (
  id         bigserial PRIMARY KEY,
  event_type text NOT NULL,
  page       text,
  user_id    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  session_id text,
  value      numeric,              -- для purchase: сумма заказа
  meta       jsonb,                -- доп. данные (order_id, product_id и т.д.)
  created_at timestamptz DEFAULT now()
);

-- Индексы для быстрой выборки по дате и типу события
CREATE INDEX IF NOT EXISTS idx_analytics_events_type_date
  ON analytics_events(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_analytics_events_date
  ON analytics_events(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_referral_rewards_referrer
  ON referral_rewards(referrer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer
  ON referrals(referrer_id);


-- ------------------------------------------------------------
-- 6. RLS (Row Level Security)
-- ------------------------------------------------------------

-- referral_codes: читать может владелец, вставлять — авторизованный
ALTER TABLE referral_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner_read_referral_code"
  ON referral_codes FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "owner_insert_referral_code"
  ON referral_codes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- referrals: читать может реферер (свои рефералы)
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "referrer_read_own_referrals"
  ON referrals FOR SELECT
  USING (auth.uid() = referrer_id);
-- Вставка — любой авторизованный (при регистрации через реферальную ссылку)
CREATE POLICY "auth_insert_referral"
  ON referrals FOR INSERT
  WITH CHECK (auth.uid() = referee_id);

-- partner_accounts: читать/обновлять только владелец
ALTER TABLE partner_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner_read_partner_account"
  ON partner_accounts FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "owner_upsert_partner_account"
  ON partner_accounts FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- referral_rewards: реферер видит свои начисления
ALTER TABLE referral_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "referrer_read_own_rewards"
  ON referral_rewards FOR SELECT
  USING (auth.uid() = referrer_id);

-- analytics_events: только вставка для авторизованных и анонимных
ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anyone_insert_analytics"
  ON analytics_events FOR INSERT
  WITH CHECK (true);


-- ------------------------------------------------------------
-- 7. SERVICE ROLE — разрешить серверные операции
--    (для начисления вознаграждений через cart.html)
-- ------------------------------------------------------------

-- partner_accounts: сервис может обновлять баланс
CREATE POLICY "service_update_partner_account"
  ON partner_accounts FOR UPDATE
  USING (true);

-- referral_rewards: сервис может вставлять записи
CREATE POLICY "service_insert_referral_reward"
  ON referral_rewards FOR INSERT
  WITH CHECK (true);

-- referral_codes: сервис может вставлять коды (при первом входе)
CREATE POLICY "service_insert_referral_code"
  ON referral_codes FOR INSERT
  WITH CHECK (true);


-- ------------------------------------------------------------
-- 8. ФУНКЦИЯ: генерация уникального реферального кода
--    Формат: MARYA-XXXX (6 символов, A-Z0-9)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  chars  text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code   text := '';
  i      int;
  exists boolean;
BEGIN
  LOOP
    code := 'MARYA-';
    FOR i IN 1..6 LOOP
      code := code || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;

    SELECT EXISTS(SELECT 1 FROM referral_codes WHERE referral_codes.code = code) INTO exists;
    EXIT WHEN NOT exists;
  END LOOP;

  RETURN code;
END;
$$;


-- ============================================================
-- ГОТОВО. Теперь можно переходить к подключению в коде.
-- ============================================================
