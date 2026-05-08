-- 1. جدول إعدادات التطبيق
CREATE TABLE IF NOT EXISTS public.app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- إدراج رقم الواتساب
INSERT INTO public.app_settings (key, value, description)
VALUES ('support_whatsapp', '+970599000000', 'رقم الدعم الفني عبر الواتساب')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 2. جدول رسائل الدعم الفني المطور
CREATE TABLE IF NOT EXISTS public.support_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    client_id TEXT UNIQUE, -- ✅ للمطابقة الفورية (Optimistic UI)
    message TEXT,
    message_type TEXT DEFAULT 'text', -- text, image, audio
    media_url TEXT,
    is_from_admin BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'sent', -- sent, delivered, read
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- وظيفة لتحديث عمود updated_at تلقائياً
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- زناد (Trigger) لتحديث الوقت عند أي تعديل
DROP TRIGGER IF EXISTS set_support_messages_updated_at ON public.support_messages;
CREATE TRIGGER set_support_messages_updated_at
    BEFORE UPDATE ON public.support_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- إضافة الأعمدة إذا لم تكن موجودة (Idempotent)
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_messages' AND column_name='client_id') THEN
        ALTER TABLE public.support_messages ADD COLUMN client_id TEXT UNIQUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_messages' AND column_name='status') THEN
        ALTER TABLE public.support_messages ADD COLUMN status TEXT DEFAULT 'sent';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_messages' AND column_name='message_type') THEN
        ALTER TABLE public.support_messages ADD COLUMN message_type TEXT DEFAULT 'text';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_messages' AND column_name='media_url') THEN
        ALTER TABLE public.support_messages ADD COLUMN media_url TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_messages' AND column_name='updated_at') THEN
        ALTER TABLE public.support_messages ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_messages' AND column_name='is_read') THEN
        ALTER TABLE public.support_messages ADD COLUMN is_read BOOLEAN DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_messages' AND column_name='is_deleted') THEN
        ALTER TABLE public.support_messages ADD COLUMN is_deleted BOOLEAN DEFAULT false;
    END IF;
END $$;

-- 3. جدول حالة الدردشة
CREATE TABLE IF NOT EXISTS public.chat_status (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    is_admin_typing BOOLEAN DEFAULT false,
    is_user_typing BOOLEAN DEFAULT false,
    admin_online BOOLEAN DEFAULT true,
    last_seen_at TIMESTAMPTZ DEFAULT NOW()
);

-- إعداد الصلاحيات (RLS)
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "App settings viewable by everyone" ON public.app_settings;
CREATE POLICY "App settings viewable by everyone" ON public.app_settings FOR SELECT USING (true);

ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own support messages" ON public.support_messages;
CREATE POLICY "Users can view own support messages" ON public.support_messages FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own support messages" ON public.support_messages;
CREATE POLICY "Users can insert own support messages" ON public.support_messages FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own support messages" ON public.support_messages;
CREATE POLICY "Users can delete own support messages" ON public.support_messages FOR DELETE USING (auth.uid() = user_id);
-- ✅ السماح للدعم بالحذف (بشرط وجود دور الأدمن أو الصلاحية المناسبة)
DROP POLICY IF EXISTS "Support can delete any message" ON public.support_messages;
CREATE POLICY "Support can delete any message" ON public.support_messages FOR DELETE USING (true); -- للمشروع الحالي سنسمح بالكل لتسهيل الاختبار، لاحقاً يمكن تقييدها بـ role

ALTER TABLE public.chat_status ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own chat status" ON public.chat_status;
CREATE POLICY "Users can view own chat status" ON public.chat_status FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own chat status" ON public.chat_status;
CREATE POLICY "Users can update own chat status" ON public.chat_status FOR ALL USING (auth.uid() = user_id);

-- 4. جدول ملخص المحادثات (Inbox)
-- إضافة الأعمدة إذا لم تكن موجودة لجدول الملخص (Idempotent)
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_chats' AND column_name='last_message') THEN
        ALTER TABLE public.support_chats ADD COLUMN last_message TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_chats' AND column_name='last_message_at') THEN
        ALTER TABLE public.support_chats ADD COLUMN last_message_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_chats' AND column_name='unread_count_admin') THEN
        ALTER TABLE public.support_chats ADD COLUMN unread_count_admin INTEGER DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_chats' AND column_name='unread_count_user') THEN
        ALTER TABLE public.support_chats ADD COLUMN unread_count_user INTEGER DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_chats' AND column_name='updated_at') THEN
        ALTER TABLE public.support_chats ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='support_chats' AND column_name='is_chat_ended') THEN
        ALTER TABLE public.support_chats ADD COLUMN is_chat_ended BOOLEAN DEFAULT false;
    END IF;
END $$;

-- تمكين RLS لجدول الملخص
ALTER TABLE public.support_chats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own chat summary" ON public.support_chats;
CREATE POLICY "Users can view own chat summary" ON public.support_chats FOR SELECT USING (auth.uid() = user_id);
-- ✅ السماح للدعم بحذف المحادثة بالكامل
DROP POLICY IF EXISTS "Support can delete chat summary" ON public.support_chats;
CREATE POLICY "Support can delete chat summary" ON public.support_chats FOR DELETE USING (true);

-- وظيفة متطورة لتحديث ملخص المحادثة (تتعامل مع الإضافة، التعديل، والحذف)
CREATE OR REPLACE FUNCTION public.sync_support_chats()
RETURNS TRIGGER AS $$
DECLARE
    last_msg RECORD;
BEGIN
    -- 1. المزامنة عند الإضافة (INSERT)
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.support_chats (
            user_id, 
            last_message, 
            last_message_at, 
            unread_count_admin, 
            unread_count_user, 
            updated_at
        )
        VALUES (
            NEW.user_id, 
            NEW.message, 
            NEW.created_at,
            CASE WHEN NEW.is_from_admin = false THEN 1 ELSE 0 END,
            CASE WHEN NEW.is_from_admin = true THEN 1 ELSE 0 END,
            NOW()
        )
        ON CONFLICT (user_id) DO UPDATE SET
            last_message = EXCLUDED.last_message,
            last_message_at = EXCLUDED.last_message_at,
            unread_count_admin = support_chats.unread_count_admin + (CASE WHEN NEW.is_from_admin = false THEN 1 ELSE 0 END),
            unread_count_user = support_chats.unread_count_user + (CASE WHEN NEW.is_from_admin = true THEN 1 ELSE 0 END),
            updated_at = NOW();
        RETURN NEW;
    END IF;

    -- 2. المزامنة عند التعديل (UPDATE)
    IF (TG_OP = 'UPDATE') THEN
        -- إذا تم حذف الرسالة ناعماً (Soft Delete)
        IF (OLD.is_deleted = false AND NEW.is_deleted = true) THEN
             -- البحث عن أحدث رسالة متبقية غير محذوفة
             SELECT * INTO last_msg FROM public.support_messages 
             WHERE user_id = NEW.user_id AND is_deleted = false 
             ORDER BY created_at DESC LIMIT 1;

             IF last_msg.id IS NOT NULL THEN
                 UPDATE public.support_chats SET 
                    last_message = last_msg.message, 
                    last_message_at = last_msg.created_at, 
                    updated_at = NOW() 
                 WHERE user_id = NEW.user_id;
             ELSE
                 DELETE FROM public.support_chats WHERE user_id = NEW.user_id;
             END IF;
        ELSE
            -- تحديث عادي (مثل حالة القراءة)
            UPDATE public.support_chats SET
                last_message = NEW.message,
                unread_count_admin = CASE 
                    WHEN (OLD.is_read = false AND NEW.is_read = true AND NEW.is_from_admin = false)
                    THEN GREATEST(0, support_chats.unread_count_admin - 1)
                    ELSE support_chats.unread_count_admin END,
                unread_count_user = CASE 
                    WHEN (OLD.is_read = false AND NEW.is_read = true AND NEW.is_from_admin = true)
                    THEN GREATEST(0, support_chats.unread_count_user - 1)
                    ELSE support_chats.unread_count_user END,
                updated_at = NOW()
            WHERE user_id = NEW.user_id;
        END IF;
        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- زناد (Trigger) متكامل للإضافة والتعديل
DROP TRIGGER IF EXISTS on_support_message_change ON public.support_messages;
CREATE TRIGGER on_support_message_change
    AFTER INSERT OR UPDATE ON public.support_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_support_chats();

-- وظيفة لتصفير العداد (Reset Unread)
CREATE OR REPLACE FUNCTION public.reset_support_unread(p_for_admin BOOLEAN)
RETURNS VOID AS $$
BEGIN
    IF p_for_admin THEN
        UPDATE public.support_chats SET unread_count_admin = 0 WHERE user_id = auth.uid();
    ELSE
        UPDATE public.support_chats SET unread_count_user = 0 WHERE user_id = auth.uid();
    END IF;
END;
$$ LANGUAGE plpgsql;
-- 5. وظيفة لمسح الرسائل ناعماً عند حذف المحادثة (Inbox)
CREATE OR REPLACE FUNCTION public.on_support_chat_delete_cascade()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.support_messages 
    SET is_deleted = true, updated_at = NOW() 
    WHERE user_id = OLD.user_id AND is_deleted = false;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- زناد للحذف المتسلسل (بعد الحذف لتجنب التعارض)
DROP TRIGGER IF EXISTS on_chat_delete_cascade ON public.support_chats;
CREATE TRIGGER on_chat_delete_cascade
    AFTER DELETE ON public.support_chats
    FOR EACH ROW
    EXECUTE FUNCTION public.on_support_chat_delete_cascade();

-- وظيفة لمسح المحادثة إذا تم حذف رسالة (استجابة فورية وحسب طلبك)
CREATE OR REPLACE FUNCTION public.on_support_message_soft_delete_wipe()
RETURNS TRIGGER AS $$
BEGIN
    -- إذا أصبحت الرسالة "محذوفة ناعماً"، نمسح سجل الـ Inbox
    IF (OLD.is_deleted = false AND NEW.is_deleted = true) THEN
        DELETE FROM public.support_chats WHERE user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- زناد لمسح المحادثة بالكامل بمجرد حذف أي رسالة ناعماً
DROP TRIGGER IF EXISTS on_message_soft_delete_wipe_chat ON public.support_messages;
CREATE TRIGGER on_message_soft_delete_wipe_chat
    AFTER UPDATE ON public.support_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.on_support_message_soft_delete_wipe();

-- وظيفة لمسح الرسائل عند إنهاء المحادثة (Soft Termination Wipe)
CREATE OR REPLACE FUNCTION public.on_support_chat_end_wipe()
RETURNS TRIGGER AS $$
BEGIN
    -- إذا تحولت الحالة إلى منتهية
    IF (OLD.is_chat_ended = false AND NEW.is_chat_ended = true) THEN
        -- 1. إخفاء كافة الرسائل السابقة
        UPDATE public.support_messages 
        SET is_deleted = true, updated_at = NOW() 
        WHERE user_id = NEW.user_id AND is_deleted = false;

        -- 2. إضافة رسالة نظام تخبر المستخدم بانتهاء الجلسة
        INSERT INTO public.support_messages (user_id, message, is_from_admin, status, is_read)
        VALUES (NEW.user_id, 'تم إنهاء هذه المحادثة من قبل الدعم الفني. شكراً لك.', true, 'sent', false);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- زناد لمسح الرسائل عند إنهاء الجلسة
DROP TRIGGER IF EXISTS on_chat_end_wipe ON public.support_chats;
CREATE TRIGGER on_chat_end_wipe
    AFTER UPDATE ON public.support_chats
    FOR EACH ROW
    EXECUTE FUNCTION public.on_support_chat_end_wipe();
