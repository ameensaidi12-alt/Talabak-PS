-- [CORRECTED] Redefine game reward functions with correct column names

-- 1. تحديث دالة إضافة النجوم (للمهمات والإنجازات)
CREATE OR REPLACE FUNCTION public.add_user_stars_v2(p_amount integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- تحديث رصيد النجوم
  UPDATE public.profiles
  SET star_points = COALESCE(star_points, 0) + p_amount
  WHERE id = v_user_id;

  -- إضافة العملية للسجل (مكافأة اللعبة أو الإنجازات)
  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (v_user_id, p_amount, 'earn', 'مكافأة اللعبة أو الإنجازات');
END;
$$;

-- 2. تحديث دالة نتائج الألعاب (تم إزالة عمود completed_at لأنه غير موجود)
CREATE OR REPLACE FUNCTION public.process_game_result_v2(
  p_game_slug text,
  p_score integer,
  p_attempt_id uuid DEFAULT NULL,
  p_is_advanced_mode boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_stars_to_award integer := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'User must be authenticated');
  END IF;

  -- تحديث محاولات اللعب (إزالة completed_at لتفادي الخطأ)
  IF p_attempt_id IS NOT NULL THEN
    UPDATE public.game_attempts
    SET 
      score = p_score,
      is_advanced_mode = p_is_advanced_mode
    WHERE id = p_attempt_id AND user_id = v_user_id;
  END IF;

  -- تحديد كمية النجوم بناءً على نوع اللعبة
  IF p_game_slug = 'fast-delivery' THEN
    v_stars_to_award := p_score;
  ELSIF p_game_slug = 'into-space' THEN
    -- في لعبة الصاروخ، النجوم تحسب من المعالم (Milestones) وتضاف عبر add_user_stars_v2
    v_stars_to_award := 0; 
  ELSE
    v_stars_to_award := p_score;
  END IF;

  IF v_stars_to_award > 0 THEN
    UPDATE public.profiles 
    SET star_points = COALESCE(star_points, 0) + v_stars_to_award 
    WHERE id = v_user_id;

    INSERT INTO public.star_points_transactions (user_id, amount, type, description)
    VALUES (v_user_id, v_stars_to_award, 'earn', 'نتائج لعبة: ' || p_game_slug);
  END IF;

  RETURN jsonb_build_object('success', true, 'awarded_stars', v_stars_to_award);
END;
$$;
