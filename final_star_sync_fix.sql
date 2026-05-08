-- HatStar Consolidated Security & Star Sync System (Final Version)

-- 1. التأكد من وجود الأعمدة
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS star_points INT DEFAULT 0;

-- 2. دالة الحماية (الحارس الذكي) مع حماية صاحب المشروع
CREATE OR REPLACE FUNCTION protect_profile_sensitive_fields()
RETURNS TRIGGER AS $$
DECLARE
    v_bypass_authorized TEXT;
    v_current_user_role user_role;
BEGIN
    -- أ. الحصول على دور الشخص الذي يحاول التعديل الآن
    BEGIN
        SELECT role INTO v_current_user_role FROM public.profiles WHERE id = auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_current_user_role := 'customer';
    END;

    -- ب. [قانون الحصانة]: يمنع منعاً باتاً تغيير رتبة أو نقاط "صاحب المشروع" من قبل أي شخص آخر
    IF OLD.id = '9071c6b2-fe0c-47b6-bea0-59581bb6b9f5' AND auth.uid() != OLD.id THEN
        RAISE EXCEPTION 'خطأ أمني: لا تملك صلاحية تعديل حساب صاحب المشروع.';
    END IF;

    -- ج. التحقق من "الإشارة السرية" للدوال المعتمدة
    BEGIN
        v_bypass_authorized := current_setting('app.authorized_update', true);
    EXCEPTION WHEN OTHERS THEN
        v_bypass_authorized := 'false';
    END;

    IF v_bypass_authorized = 'true' THEN
        RETURN NEW;
    END IF;

    -- د. الأدمن يمكنه تعديل الآخرين (إلا صاحب المشروع كما مر في الخطوة ب)
    IF v_current_user_role = 'admin' THEN
        RETURN NEW;
    END IF;

    -- هـ. الزبون لا يمكنه تعديل الحقول الحساسة (النقاط أو الدور)
    IF NEW.role IS DISTINCT FROM OLD.role OR NEW.star_points IS DISTINCT FROM OLD.star_points THEN
        RAISE EXCEPTION 'لا تملك صلاحية تعديل هذه الحقول. (نظام حماية Talabak PS)';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. تفعيل الحارس على جدول البروفايلات
DROP TRIGGER IF EXISTS tr_protect_profile_fields ON public.profiles;
CREATE TRIGGER tr_protect_profile_fields
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION protect_profile_sensitive_fields();

-- 4. دالة المزامنة الآلية (تحمل المفتاح السري لتجاوز الرقابة)
CREATE OR REPLACE FUNCTION sync_user_star_points()
RETURNS TRIGGER AS $$
BEGIN
  -- تفعيل الإشارة السرية محلياً لتجاوز الحارس الذكي
  PERFORM set_config('app.authorized_update', 'true', true);

  IF (TG_OP = 'INSERT') THEN
    UPDATE public.profiles
    SET star_points = COALESCE(star_points, 0) + NEW.amount
    WHERE id = NEW.user_id;
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE public.profiles
    SET star_points = COALESCE(star_points, 0) - OLD.amount
    WHERE id = OLD.user_id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. تفعيل زناد المزامنة
DROP TRIGGER IF EXISTS tr_sync_star_points ON public.star_points_transactions;
CREATE TRIGGER tr_sync_star_points
AFTER INSERT OR DELETE ON public.star_points_transactions
FOR EACH ROW
EXECUTE FUNCTION sync_user_star_points();

-- 6. دالة الربح الآمنة للألعاب (add_user_stars_secure_v1)
CREATE OR REPLACE FUNCTION add_user_stars_secure_v1(p_amount INT, p_ts BIGINT, p_sig TEXT)
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
  VALUES (auth.uid(), p_amount, 'earn', 'ربح معتمد من اللعبة');

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 7. دالة الأدمن لتعديل النجوم يدوياً (للهدايا أو التعويضات)
CREATE OR REPLACE FUNCTION adjust_star_points_admin(
  p_user_id UUID,
  p_amount  INT,
  p_reason  TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_role user_role;
BEGIN
  -- التأكد من أن المنفذ هو أدمن
  SELECT role INTO v_role FROM public.profiles WHERE id = v_admin_id;
  IF v_role != 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized_role');
  END IF;

  -- إضافة العملية للسجل (المزامنة ستحدث الرصيد تلقائياً)
  INSERT INTO public.star_points_transactions (user_id, amount, type, description)
  VALUES (p_user_id, p_amount, 'earn', 'تعديل إداري: ' || COALESCE(p_reason, 'بدون سبب'));

  RETURN jsonb_build_object('success', true);
END;
$$;
