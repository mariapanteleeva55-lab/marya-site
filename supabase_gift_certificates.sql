-- ═══════════════════════════════════════════════════════════
--  МАРЬЯ — Подарочные сертификаты
--  Запустить в Supabase → SQL Editor
-- ═══════════════════════════════════════════════════════════

-- 1. Таблица сертификатов
CREATE TABLE IF NOT EXISTS gift_certificates (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  code            TEXT        UNIQUE NOT NULL,
  design_id       INTEGER     NOT NULL CHECK (design_id BETWEEN 1 AND 6),
  nominal         INTEGER     NOT NULL CHECK (nominal IN (500, 1000, 2000, 3000, 5000, 10000)),
  balance         INTEGER     NOT NULL,
  sender_name     TEXT        NOT NULL,
  sender_email    TEXT        NOT NULL,
  recipient_name  TEXT        NOT NULL,
  recipient_email TEXT        NOT NULL,
  message         TEXT        DEFAULT '',
  send_date       DATE        NOT NULL,
  send_now        BOOLEAN     DEFAULT TRUE,
  status          TEXT        NOT NULL DEFAULT 'pending_payment'
                  CHECK (status IN (
                    'pending_payment',  -- ожидает оплаты
                    'scheduled',        -- оплачен, ждёт отправки по дате
                    'active',           -- активен, можно использовать
                    'partially_used',   -- частично использован
                    'used',             -- полностью использован
                    'expired'           -- истёк срок
                  )),
  order_id        TEXT,                 -- ID заказа покупки сертификата
  used_in_orders  JSONB       DEFAULT '[]', -- история применения к заказам
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  activated_at    TIMESTAMPTZ,
  sent_at         TIMESTAMPTZ,
  expires_at      DATE GENERATED ALWAYS AS (send_date + INTERVAL '1 year') STORED,
  CONSTRAINT valid_balance CHECK (balance >= 0 AND balance <= nominal)
);

-- 2. Функция генерации кода сертификата
CREATE OR REPLACE FUNCTION generate_cert_code()
RETURNS TEXT AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code  TEXT;
  part1 TEXT := '';
  part2 TEXT := '';
  i     INTEGER;
  exists_check INTEGER;
BEGIN
  LOOP
    part1 := '';
    part2 := '';
    FOR i IN 1..4 LOOP
      part1 := part1 || substr(chars, floor(random() * length(chars) + 1)::INTEGER, 1);
    END LOOP;
    FOR i IN 1..4 LOOP
      part2 := part2 || substr(chars, floor(random() * length(chars) + 1)::INTEGER, 1);
    END LOOP;
    code := 'MARYA-' || part1 || '-' || part2;

    SELECT COUNT(*) INTO exists_check FROM gift_certificates WHERE gift_certificates.code = code;
    EXIT WHEN exists_check = 0;
  END LOOP;
  RETURN code;
END;
$$ LANGUAGE plpgsql;

-- 3. Триггер: авто-генерация кода + установка balance = nominal
CREATE OR REPLACE FUNCTION before_insert_certificate()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.code IS NULL OR NEW.code = '' THEN
    NEW.code := generate_cert_code();
  END IF;
  IF NEW.balance IS NULL THEN
    NEW.balance := NEW.nominal;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trig_cert_before_insert ON gift_certificates;
CREATE TRIGGER trig_cert_before_insert
  BEFORE INSERT ON gift_certificates
  FOR EACH ROW EXECUTE FUNCTION before_insert_certificate();

-- 4. Функция применения сертификата к заказу
--    Возвращает: applied_amount (сколько списано), new_balance, success
CREATE OR REPLACE FUNCTION apply_gift_certificate(
  p_code       TEXT,
  p_order_id   TEXT,
  p_amount     INTEGER   -- сумма заказа, которую нужно покрыть
)
RETURNS JSONB AS $$
DECLARE
  cert         gift_certificates%ROWTYPE;
  apply_amount INTEGER;
BEGIN
  -- Найти сертификат
  SELECT * INTO cert FROM gift_certificates
  WHERE code = p_code
    AND status IN ('active', 'partially_used')
    AND expires_at >= CURRENT_DATE
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Сертификат не найден или недействителен');
  END IF;

  -- Сколько можно списать
  apply_amount := LEAST(cert.balance, p_amount);

  -- Обновить сертификат
  UPDATE gift_certificates SET
    balance        = balance - apply_amount,
    status         = CASE
                       WHEN balance - apply_amount = 0 THEN 'used'
                       ELSE 'partially_used'
                     END,
    used_in_orders = used_in_orders || jsonb_build_object(
                       'order_id', p_order_id,
                       'amount',   apply_amount,
                       'date',     NOW()
                     )
  WHERE id = cert.id;

  RETURN jsonb_build_object(
    'success',        true,
    'applied_amount', apply_amount,
    'new_balance',    cert.balance - apply_amount,
    'cert_id',        cert.id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Функция проверки сертификата (без списания)
CREATE OR REPLACE FUNCTION check_gift_certificate(p_code TEXT)
RETURNS JSONB AS $$
DECLARE
  cert gift_certificates%ROWTYPE;
BEGIN
  SELECT * INTO cert FROM gift_certificates WHERE code = p_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Сертификат не найден');
  END IF;

  IF cert.status = 'pending_payment' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Сертификат ещё не оплачен');
  END IF;

  IF cert.status = 'used' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Сертификат уже использован');
  END IF;

  IF cert.status = 'expired' OR cert.expires_at < CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Срок действия сертификата истёк');
  END IF;

  IF cert.status NOT IN ('active', 'partially_used') THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Сертификат недействителен');
  END IF;

  RETURN jsonb_build_object(
    'valid',           true,
    'balance',         cert.balance,
    'nominal',         cert.nominal,
    'recipient_name',  cert.recipient_name,
    'expires_at',      cert.expires_at,
    'status',          cert.status
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RLS политики
ALTER TABLE gift_certificates ENABLE ROW LEVEL SECURITY;

-- Анонимные могут создавать (шаг оформления до авторизации)
CREATE POLICY "anon_insert_cert" ON gift_certificates
  FOR INSERT TO anon, authenticated WITH CHECK (true);

-- Анонимные могут читать по коду (для check_gift_certificate)
CREATE POLICY "anon_read_by_code" ON gift_certificates
  FOR SELECT TO anon, authenticated USING (true);

-- Только сам пользователь может обновить свой сертификат
-- (обновления идут через SECURITY DEFINER функции выше)

-- 7. Индексы
CREATE INDEX IF NOT EXISTS idx_cert_code     ON gift_certificates(code);
CREATE INDEX IF NOT EXISTS idx_cert_status   ON gift_certificates(status);
CREATE INDEX IF NOT EXISTS idx_cert_senddate ON gift_certificates(send_date) WHERE status = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_cert_expires  ON gift_certificates(expires_at);

-- ═══════════════════════════════════════════════════════════
--  Edge Function для планового отправления сертификатов
--  (необязательно — для автоматической отправки по дате)
--
--  1. Создайте Edge Function: supabase functions new send-scheduled-certs
--  2. Используйте код из файла edge-functions/send-scheduled-certs/index.ts
--  3. Запланируйте через pg_cron:
--
--  SELECT cron.schedule(
--    'send-scheduled-certs',
--    '0 9 * * *',   -- каждый день в 9:00 UTC
--    $$
--    SELECT net.http_post(
--      url := 'https://cizdsiqolarjcgmwbafp.supabase.co/functions/v1/send-scheduled-certs',
--      headers := '{"Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb
--    );
--    $$
--  );
-- ═══════════════════════════════════════════════════════════

SELECT 'Таблица gift_certificates создана успешно!' AS result;
