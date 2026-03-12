-- ── SKIN PROFILES (квиз подбора ухода) ─────────────────────────────────────
-- Запустить в Supabase SQL Editor

CREATE TABLE IF NOT EXISTS skin_profiles (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  q1_day       text,
  q2_wash      text,
  q3_concerns  text[],
  q4_age       text,
  q5_wrinkles  text,
  q6_eyes      text,
  q7_look      text,
  q8_routine   text,
  skin_type    text,   -- oily | dry | combo | sensitive | normal
  skin_label   text,
  skin_desc    text,
  product_ids  int[],
  updated_at   timestamptz DEFAULT now(),
  UNIQUE(user_id)
);

ALTER TABLE skin_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own skin profile"
  ON skin_profiles
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
