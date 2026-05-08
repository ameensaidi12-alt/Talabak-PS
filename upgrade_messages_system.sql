-- HatStar Final Upgrade: Creative Messages System

-- 1. تحديث دالة الربح لتشمل الوصف المخصص
CREATE OR REPLACE FUNCTION add_user_stars_secure_v1(
  p_amount INT, 
  p_ts BIGINT, 
  p_sig TEXT,
  p_description TEXT DEFAULT 'ربح من اللعبة'
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_secret TEXT := 'HS2026@HatStar#Secure!K3y$';
  v_expected TEXT;
BEGIN
  -- التحقق من التوقيع (لا يشمل الوصف لسهولة البرمجة ومنع التعقيد)
  v_expected := encode(hmac(convert_to('stars:'||p_amount||':'||p_ts, 'utf8'), convert_to(v_secret, 'utf8'), 'sha256'), 'hex');
  
  IF LOWER(p_sig) != LOWER(v_expected) THEN 
    RETURN jsonb_build_object('success', false, 'error', 'sig_error'); 
  END IF;

  -- إضافة العملية للسجل بالوصف المخصص (جماليات)
  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (auth.uid(), p_amount, 'earn', p_description);

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 2. تحديث دالة الأدمن لتحسين النص الافتراضي
CREATE OR REPLACE FUNCTION adjust_star_points_admin(
  p_user_id UUID,
  p_amount  INT,
  p_reason  TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_role user_role;
  v_final_desc TEXT;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE id = v_admin_id;
  IF v_role != 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;

  v_final_desc := CASE 
    WHEN p_amount > 0 THEN '💎 هدية ملكية: ' || COALESCE(p_reason, 'تقدير من الإدارة')
    ELSE '⚠️ تعديل إداري: ' || COALESCE(p_reason, 'خصم نقاط')
  END;

  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (p_user_id, p_amount, 'earn', v_final_desc);

  RETURN jsonb_build_object('success', true);
END;
$$;
