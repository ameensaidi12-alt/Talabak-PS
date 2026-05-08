-- HatStar Royal Rewards System (المحرك النهائي والمطور)

-- 1. التأكد من وجود الأعمدة
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS star_points INT DEFAULT 0;

-- 2. دالة الحماية (الحارس الذكي) - نسخة HatStar المحدثة
CREATE OR REPLACE FUNCTION protect_profile_sensitive_fields()
RETURNS TRIGGER AS $$
DECLARE
    v_bypass_authorized TEXT;
    v_current_user_role user_role;
BEGIN
    BEGIN
        SELECT role INTO v_current_user_role FROM public.profiles WHERE id = auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_current_user_role := 'customer';
    END;

    -- ب. [قانون الحصانة]: حماية صاحب المشروع من أي تعديل خارجي
    IF OLD.id = '9071c6b2-fe0c-47b6-bea0-59581bb6b9f5' AND auth.uid() != OLD.id THEN
        RAISE EXCEPTION 'خطأ أمني: لا تملك صلاحية تعديل حساب صاحب المشروع.';
    END IF;

    -- ج. [صلاحية المالك]: إذا كنت أنت صاحب المشروع، لك كامل الصلاحيات ولا ينطبق عليك أي حظر
    IF auth.uid() = '9071c6b2-fe0c-47b6-bea0-59581bb6b9f5' THEN
        RETURN NEW;
    END IF;

    BEGIN
        v_bypass_authorized := current_setting('app.authorized_update', true);
    EXCEPTION WHEN OTHERS THEN
        v_bypass_authorized := 'false';
    END;

    IF v_bypass_authorized = 'true' OR v_current_user_role = 'admin' THEN
        RETURN NEW;
    END IF;

    IF NEW.role IS DISTINCT FROM OLD.role OR NEW.star_points IS DISTINCT FROM OLD.star_points THEN
        RAISE EXCEPTION 'لا تملك صلاحية تعديل هذه الحقول. (نظام حماية HatStar)';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_protect_profile_fields ON public.profiles;
CREATE TRIGGER tr_protect_profile_fields
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION protect_profile_sensitive_fields();

-- 3. دالة المزامنة الآلية
CREATE OR REPLACE FUNCTION sync_user_star_points()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM set_config('app.authorized_update', 'true', true);
  IF (TG_OP = 'INSERT') THEN
    UPDATE public.profiles SET star_points = COALESCE(star_points, 0) + NEW.amount WHERE id = NEW.user_id;
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE public.profiles SET star_points = COALESCE(star_points, 0) - OLD.amount WHERE id = OLD.user_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_sync_star_points ON public.star_points_transactions;
CREATE TRIGGER tr_sync_star_points
AFTER INSERT OR DELETE ON public.star_points_transactions
FOR EACH ROW
EXECUTE FUNCTION sync_user_star_points();

-- 4. دالة الربح الآمنة مع "الوصف الذكي" (للصاروخ والتوصيل)
-- نحذف أي نسخة قديمة باختلاف أنواع البيانات لضمان عدم حدوث تعارض
DROP FUNCTION IF EXISTS public.add_user_stars_secure_v1(UUID, INT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.add_user_stars_secure_v1(INT, BIGINT, TEXT);
DROP FUNCTION IF EXISTS public.add_user_stars_secure_v1(INT, BIGINT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION add_user_stars_secure_v1(
  p_amount INT, 
  p_ts BIGINT, 
  p_sig TEXT,
  p_description TEXT DEFAULT '🎮 ربح من اللعبة'
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

-- 5. دالة مكافأة الطلبات الآلية
CREATE OR REPLACE FUNCTION award_stars_for_order()
RETURNS TRIGGER AS $$
DECLARE
  v_ratio DECIMAL;
  v_stars INTEGER;
BEGIN
  IF (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'delivered') THEN
    SELECT CAST(purchase_to_stars_ratio AS DECIMAL) INTO v_ratio FROM space_game_settings WHERE id = 1;
    v_ratio := COALESCE(v_ratio, 1.0);
    v_stars := FLOOR(NEW.total_price * v_ratio);

    IF v_stars > 0 THEN
      INSERT INTO public.star_points_transactions (user_id, amount, type, description)
      VALUES (NEW.user_id, v_stars, 'earn', '🛍️ شكراً لثقتك! ربحت ' || v_stars || ' نجوم مقابل طلبك الأخير');
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_award_order_stars ON public.orders;
CREATE TRIGGER tr_award_order_stars
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION award_stars_for_order();

-- 6. دالة الإضافة اليدوية (هدايا الأدمن)
-- نحذف النسخة القديمة أولاً لكي نتمكن من تغيير نوع الاستجابة لـ JSONB
DROP FUNCTION IF EXISTS public.adjust_star_points_admin(UUID, INT, TEXT);
DROP FUNCTION IF EXISTS public.adjust_star_points_admin(UUID, INTEGER, TEXT);

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
  IF v_role != 'admin' THEN RETURN jsonb_build_object('success', false, 'error', 'unauthorized'); END IF;

  v_final_desc := CASE 
    WHEN p_amount > 0 THEN '💎 هدية ملكية: ' || COALESCE(p_reason, 'تقدير من الإدارة')
    ELSE '⚠️ تعديل إداري: ' || COALESCE(p_reason, 'خصم نقاط')
  END;

  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (p_user_id, p_amount, 'earn', v_final_desc);

  RETURN jsonb_build_object('success', true);
END;
$$;
