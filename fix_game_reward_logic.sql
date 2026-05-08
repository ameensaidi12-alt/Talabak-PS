-- [FIXED] Redefine game reward system to use dynamic ratio and minimum score
-- هذا الكود يصلح مشكلة احتساب النجوم في لعبة التوصيل (منع توزيع النجوم إذا كان السكور أقل من 50، وتطبيق نسبة 10:1)

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
  v_ratio integer;
  v_min_score integer;
  v_settings_table text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'User must be authenticated');
  END IF;

  -- 1. تحديث سجل محاولة اللعب إن وُجد
  IF p_attempt_id IS NOT NULL THEN
    UPDATE public.game_attempts
    SET 
      score = p_score,
      is_advanced_mode = p_is_advanced_mode
    WHERE id = p_attempt_id AND user_id = v_user_id;
  END IF;

  -- 2. تحديد جدول الإعدادات بناءً على نوع اللعبة
  v_settings_table := CASE WHEN p_game_slug = 'into-space' THEN 'space_game_settings' ELSE 'game_settings' END;

  -- 3. جلب الإعدادات الحالية من الداتابيس (النسبة والحد الأدنى)
  -- نستخدم EXECUTE لأن اسم الجدول متغير
  EXECUTE format('SELECT points_to_stars_ratio, min_score_for_reward FROM public.%I WHERE id = 1', v_settings_table)
  INTO v_ratio, v_min_score;

  -- قيم افتراضية للأمان في حال لم توجد الإعدادات
  v_ratio := COALESCE(v_ratio, 10);
  v_min_score := COALESCE(v_min_score, 50);

  -- 4. تطبيق منطق المكافأة (Reward Logic)
  -- إذا كان السكور أقل من الحد الأدنى، لا يوجد نجوم
  IF p_score >= v_min_score THEN
    -- تقسيم السكور على النسبة (مثلاً 10) للحصول على النجوم
    v_stars_to_award := FLOOR(p_score / v_ratio);
  ELSE
    v_stars_to_award := 0;
  END IF;

  -- 5. إذا كانت النجوم أكبر من صفر، قم بتحديث الرصيد وتسجيل العملية
  IF v_stars_to_award > 0 THEN
    -- تحديث رصيد المستخدم في جدول البروفايل
    UPDATE public.profiles 
    SET star_points = COALESCE(star_points, 0) + v_stars_to_award 
    WHERE id = v_user_id;

    -- تسجيل العملية في سجل المعاملات لتظهر في "سجل النجوم" بالتطبيق
    INSERT INTO public.star_points_transactions (user_id, amount, type, description)
    VALUES (v_user_id, v_stars_to_award, 'earn', 'نتائج لعبة: ' || p_game_slug);
  END IF;

  -- إرجاع النتيجة للتطبيق
  RETURN jsonb_build_object(
    'success', true, 
    'awarded_stars', v_stars_to_award,
    'applied_ratio', v_ratio,
    'applied_min_score', v_min_score
  );
END;
$$;
