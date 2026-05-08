-- Redefine add_user_stars_v2 to include transaction logging
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

  -- 1. Atomic update to profiles
  UPDATE public.profiles
  SET star_points = COALESCE(star_points, 0) + p_amount
  WHERE id = v_user_id;

  -- 2. Log transaction for the history screen
  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (v_user_id, p_amount, 'earn', 'مكافأة اللعبة أو الإنجازات');
END;
$$;

-- Note: process_game_result_v2 should also log transactions if it awards stars.
-- Since the exact logic varies by game slug, we ensure that if p_score is treated as stars, it is logged.
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

  -- 1. Update/Insert into game_attempts
  IF p_attempt_id IS NOT NULL THEN
    UPDATE public.game_attempts
    SET 
      score = p_score,
      completed_at = now(),
      is_advanced_mode = p_is_advanced_mode
    WHERE id = p_attempt_id AND user_id = v_user_id;
  END IF;

  -- 2. Logic for awarding stars (Game dependent)
  -- For into-space, score is altitude (stars are handled separately via add_user_stars_v2 for milestones)
  -- For fast-delivery and others, score IS usually the stars/points earned
  IF p_game_slug = 'fast-delivery' THEN
    v_stars_to_award := p_score;
  END IF;

  IF v_stars_to_award > 0 THEN
    -- Update profile
    UPDATE public.profiles 
    SET star_points = COALESCE(star_points, 0) + v_stars_to_award 
    WHERE id = v_user_id;

    -- Log transaction
    INSERT INTO public.star_points_transactions (user_id, amount, type, description)
    VALUES (v_user_id, v_stars_to_award, 'earn', 'نتائج لعبة: ' || p_game_slug);
  END IF;

  RETURN jsonb_build_object('success', true, 'awarded_stars', v_stars_to_award);
END;
$$;
