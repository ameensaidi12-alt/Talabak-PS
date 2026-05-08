-- HATSTAR EXPANSION TABLES (ADVANCED FEATURES)

-- 1. User Addresses
CREATE TABLE user_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL, -- e.g., 'Home', 'Office'
    address_line_1 TEXT NOT NULL,
    address_line_2 TEXT,
    city TEXT,
    location GEOGRAPHY(POINT),
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Coupons / Promo Codes
CREATE TABLE coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    discount_type TEXT CHECK (discount_type IN ('percentage', 'fixed')),
    discount_value DECIMAL(10,2) NOT NULL,
    min_order_value DECIMAL(10,2) DEFAULT 0.00,
    valid_from TIMESTAMPTZ DEFAULT NOW(),
    valid_until TIMESTAMPTZ,
    usage_limit INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Favorite Vendors (Wishlist)
CREATE TABLE favorite_vendors (
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    vendor_id UUID REFERENCES vendors(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, vendor_id)
);

-- RLS for Expansion
ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own addresses" ON user_addresses FOR ALL USING (auth.uid() = user_id);

ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Everyone view valid coupons" ON coupons FOR SELECT USING (NOW() < valid_until OR valid_until IS NULL);

ALTER TABLE favorite_vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own favorites" ON favorite_vendors FOR ALL USING (auth.uid() = user_id);
