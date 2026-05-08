-- HatStar Royal Rewards System (Final Consolidated SQL)

-- 1. تحديث دالة الربح المعتمد لتشمل الوصف المخصص
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
  v_expected := encode(hmac(convert_to('stars:'||p_amount||':'||p_ts, 'utf8'), convert_to(v_secret, 'utf8'), 'sha256'), 'hex');
  IF LOWER(p_sig) != LOWER(v_expected) THEN 
    RETURN jsonb_build_object('success', false, 'error', 'sig_error'); 
  END IF;

  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (auth.uid(), p_amount, 'earn', p_description);

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 2. تحديث دالة الأدمن برسائل فخمة للهدايا
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

  -- صياغة رسالة فخمة
  v_final_desc := CASE 
    WHEN p_amount > 0 THEN '💎 هدية ملكية: ' || COALESCE(p_reason, 'تقدير من الإدارة')
    ELSE '⚠️ تعديل إداري: ' || COALESCE(p_reason, 'خصم نقاط')
  END;

  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (p_user_id, p_amount, 'earn', v_final_desc);

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 3. تفعيل نظام مكافآت الطلبات المكتملة (آلياً)
CREATE OR REPLACE FUNCTION award_stars_for_order()
RETURNS TRIGGER AS $$
DECLARE
  v_ratio DECIMAL;
  v_stars INTEGER;
  v_desc TEXT;
BEGIN
  -- يتم المنح فقط عند تغيير الحالة إلى 'delivered'
  IF (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'delivered') THEN
    -- جلب نسبة المكافأة من الإعدادات (نجم لكل 1 شيكل مثلاً)
    BEGIN
        SELECT CAST(purchase_to_stars_ratio AS DECIMAL) INTO v_ratio FROM space_game_settings WHERE id = 1;
    EXCEPTION WHEN OTHERS THEN
        v_ratio := 1.0;
    END;
    
    IF v_ratio IS NULL THEN v_ratio := 1.0; END IF;

    -- حساب النجوم بناءً على قيمة الطلب الكلية
    v_stars := FLOOR(NEW.total_price * v_ratio);

    IF v_stars > 0 THEN
      v_desc := '🛍️ شكراً لثقتك! ربحت ' || v_stars || ' نجوم مقابل طلبك رقم #' || NEW.id;

      -- إضافة العملية للسجل (سيقوم زناد المزامنة بتحديث الرصيد)
      INSERT INTO public.star_points_transactions (user_id, amount, type, description)
      VALUES (NEW.user_id, v_stars, 'earn', v_desc);
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ربط الزناد بجدول الطلبات
DROP TRIGGER IF EXISTS tr_award_order_stars ON public.orders;
CREATE TRIGGER tr_award_order_stars
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION award_stars_for_order();
