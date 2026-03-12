-- ── HABIT LOGS (трекер ежедневного ухода) ────────────────────────
-- Запустить в Supabase SQL Editor

CREATE TABLE IF NOT EXISTS habit_logs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  log_date   date NOT NULL,
  morning    boolean NOT NULL DEFAULT false,
  evening    boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, log_date)
);

ALTER TABLE habit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own habit logs" ON habit_logs;
CREATE POLICY "Users manage own habit logs"
  ON habit_logs
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
