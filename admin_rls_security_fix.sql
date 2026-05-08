-- 1. تفعيل الحماية لجداول العناوين والألعاب والمعاملات
ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.star_points_transactions ENABLE ROW LEVEL SECURITY;

-- 2. سياسة العناوين: الأدمن يرى الكل، المستخدم يرى نفسه فقط
DROP POLICY IF EXISTS "Users manage own addresses" ON public.user_addresses;
CREATE POLICY "Users manage own addresses" ON public.user_addresses FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view all addresses" ON public.user_addresses;
CREATE POLICY "Admins can view all addresses" ON public.user_addresses FOR SELECT 
USING ((SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

-- 3. سياسة تقدم الألعاب: الأدمن يرى الكل، المستخدم يرى نفسه فقط
DROP POLICY IF EXISTS "Users manage own game progress" ON public.game_progress;
CREATE POLICY "Users manage own game progress" ON public.game_progress FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view all game progress" ON public.game_progress;
CREATE POLICY "Admins can view all game progress" ON public.game_progress FOR SELECT 
USING ((SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

-- 4. سياسة المعاملات: الأدمن يرى الكل، المستخدم يرى نفسه فقط
DROP POLICY IF EXISTS "Users view own transactions" ON public.star_points_transactions;
CREATE POLICY "Users view own transactions" ON public.star_points_transactions FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view all transactions" ON public.star_points_transactions;
CREATE POLICY "Admins can view all transactions" ON public.star_points_transactions FOR SELECT 
USING ((SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');
