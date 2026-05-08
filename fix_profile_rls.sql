-- تفعيل RLS لجدول البروفايل في حال لم يكن مفعلاً
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 1. السماح للجميع بقراءة الملفات الشخصية (ضروري لكي تعمل سياسات التحديث بدون مشاكل)
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
CREATE POLICY "Public profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);

-- 2. السماح للمستخدم بتحديث ملفه الشخصي الخاص به فقط
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- 3. السماح للمستخدم بإدراج ملفه الشخصي (لتجنب الأخطاء عند التسجيل إذا لزم الأمر)
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- 4. السماح للمدراء (Admins) بتعديل أي حساب من لوحة التحكم
DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles;
CREATE POLICY "Admins can update any profile" ON public.profiles FOR UPDATE USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
);
