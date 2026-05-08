-- حل مشكلة الصلاحيات لتحديث الرتب (Role Update Fix)

-- إنشاء دالة آمنة للأدمن لتغيير رتب المستخدمين متجاوزة قيود RLS
CREATE OR REPLACE FUNCTION admin_set_user_role(
  p_target_user_id UUID,
  p_new_role TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_executor_role TEXT;
  v_executor_id UUID := auth.uid();
BEGIN
  -- 1. جلب رتبة منفذ الأمر
  SELECT role INTO v_executor_role FROM public.profiles WHERE id = v_executor_id;

  -- 2. التحقق من الصلاحيات: يجب أن يكون أدمن أو المالك
  IF v_executor_role != 'admin' AND v_executor_id != '9071c6b2-fe0c-47b6-bea0-59581bb6b9f5' THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح لك بإجراء هذا التعديل.');
  END IF;

  -- 3. تفعيل وضع المزامنة لتجاوز الحارس الذكي للرتب
  PERFORM set_config('app.authorized_update', 'true', true);

  -- 4. تنفيذ التعديل
  UPDATE public.profiles 
  SET role = p_new_role::user_role 
  WHERE id = p_target_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
