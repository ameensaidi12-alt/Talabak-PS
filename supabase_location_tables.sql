-- 1. إنشاء جدول المناطق والقرى
CREATE TABLE public.delivery_areas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    parent_id UUID REFERENCES public.delivery_areas(id) ON DELETE SET NULL, -- للتقسيم الفرعي (مثل أحياء داخل مدينة)
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. إنشاء جدول عناوين المستخدمين المتطور
CREATE TABLE public.user_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    area_id UUID REFERENCES public.delivery_areas(id) ON DELETE SET NULL,
    title TEXT, -- منزل، عمل، الخ
    address_line_1 TEXT, -- الشارع والمبنى
    building_number TEXT,
    floor_number TEXT,
    apartment_number TEXT,
    location GEOGRAPHY(POINT), -- إحداثيات GPS من الخريطة
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. بيانات أولية للمناطق (كما في الصورة)
INSERT INTO public.delivery_areas (name) VALUES 
('القدس'),
('الناصرة وضواحيها'),
('ام الفحم'),
('باقة الغربية'),
('حيفا'),
('رهط'),
('سخنين - عرابة - دير حنا'),
('جديدة المكر - يركا - ياسيف'),
('الطيبة - الطيرة - قلنسوة');

-- 4. إعداد الصلاحيات (RLS)
ALTER TABLE public.delivery_areas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Delivery areas viewable by everyone" ON public.delivery_areas FOR SELECT USING (true);

ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own addresses" ON public.user_addresses FOR ALL USING (auth.uid() = user_id);
