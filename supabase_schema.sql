-- MULTI-VENDOR DELIVERY APP SCHEMA (SUPABASE)

-- 0. Enable PostGIS Extension (Mandatory for proximity features)
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Profiles & Auth
CREATE TYPE user_role AS ENUM ('customer', 'vendor', 'driver', 'admin');

CREATE TABLE profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    full_name TEXT,
    phone TEXT UNIQUE,
    avatar_url TEXT,
    role user_role DEFAULT 'customer',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Vendors
CREATE TYPE vendor_type AS ENUM ('restaurant', 'supermarket', 'retail');

CREATE TABLE vendors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES profiles(id),
    name TEXT NOT NULL,
    logo_url TEXT,
    cover_image_url TEXT,
    type vendor_type NOT NULL,
    description TEXT,
    is_open BOOLEAN DEFAULT true,
    delivery_fee DECIMAL(10,2) DEFAULT 0.00,
    estimated_delivery_time TEXT, -- e.g., '25-35 min'
    rating_avg DECIMAL(3,2) DEFAULT 0.00,
    address TEXT,
    location GEOGRAPHY(POINT), -- PostGIS for proximity
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Categories
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID REFERENCES vendors(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Products
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID REFERENCES vendors(id) ON DELETE CASCADE,
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    description TEXT,
    base_price DECIMAL(10,2) NOT NULL,
    image_url TEXT,
    is_available BOOLEAN DEFAULT true,
    product_type TEXT, -- food, grocery, etc.
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Product Options
CREATE TABLE product_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    name TEXT NOT NULL, -- e.g., 'Size', 'Extra Toppings'
    is_required BOOLEAN DEFAULT false,
    is_multiple BOOLEAN DEFAULT false, -- Checkboxes vs Radios
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE product_option_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    option_id UUID REFERENCES product_options(id) ON DELETE CASCADE,
    name TEXT NOT NULL, -- e.g., 'Large', 'Extra Cheese'
    price_modifier DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Cart (Unified)
CREATE TABLE carts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

CREATE TABLE cart_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id UUID REFERENCES carts(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id),
    vendor_id UUID REFERENCES vendors(id),
    quantity INT DEFAULT 1,
    selected_options JSONB DEFAULT '[]', -- Stores option IDs and names
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Orders
CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'preparing', 'out_for_delivery', 'delivered', 'cancelled');

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id),
    vendor_id UUID REFERENCES vendors(id),
    driver_id UUID REFERENCES profiles(id),
    status order_status DEFAULT 'pending',
    subtotal DECIMAL(10,2) NOT NULL,
    delivery_fee DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    delivery_address TEXT,
    delivery_location GEOGRAPHY(POINT),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id),
    name TEXT NOT NULL,
    quantity INT NOT NULL,
    price_at_time DECIMAL(10,2) NOT NULL,
    selected_options JSONB DEFAULT '[]'
);

-- 8. Drivers
CREATE TABLE drivers (
    profile_id UUID REFERENCES profiles(id) PRIMARY KEY,
    is_available BOOLEAN DEFAULT false,
    live_location GEOGRAPHY(POINT),
    vehicle_type TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Reviews
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id),
    vendor_id UUID REFERENCES vendors(id),
    order_id UUID REFERENCES orders(id),
    rating INT CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS POLICIES --

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public profiles are viewable by everyone" ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Vendors are viewable by everyone" ON vendors FOR SELECT USING (true);
CREATE POLICY "Vendors manage own data" ON vendors FOR ALL USING (auth.uid() = owner_id);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Products viewable by everyone" ON products FOR SELECT USING (true);

ALTER TABLE carts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see own cart" ON carts FOR SELECT USING (auth.uid() = user_id);

ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own cart items" ON cart_items FOR ALL 
USING (EXISTS (SELECT 1 FROM carts WHERE id = cart_items.cart_id AND user_id = auth.uid()));

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own orders" ON orders FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Vendors see their orders" ON orders FOR SELECT USING (EXISTS (SELECT 1 FROM vendors WHERE id = orders.vendor_id AND owner_id = auth.uid()));
CREATE POLICY "Drivers see assigned orders" ON orders FOR SELECT USING (auth.uid() = driver_id);

-- REALTIME CONFIG --
ALTER PUBLICATION supabase_realtime ADD TABLE orders, drivers;

-- TRIGGERS FOR NOTIFICATIONS --

-- 1. Create notification on order status change
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF (OLD.status IS DISTINCT FROM NEW.status) THEN
    INSERT INTO notifications (user_id, title, content)
    VALUES (
      NEW.user_id,
      'Order Update',
      'Your order #' || NEW.id || ' is now ' || NEW.status
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_order_status_change
AFTER UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_order_status_change();

-- 2. Notify vendor on new order
CREATE OR REPLACE FUNCTION notify_new_order_to_vendor()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_id UUID;
BEGIN
  SELECT owner_id INTO v_owner_id FROM vendors WHERE id = NEW.vendor_id;
  INSERT INTO notifications (user_id, title, content)
  VALUES (
    v_owner_id,
    'New Order Received!',
    'You have a new order: #' || NEW.id
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_new_order_vendor
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_new_order_to_vendor();

-- STORAGE BUCKETS SETUP (To be run via Supabase Dashboard or API) --
-- Insert into storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);
-- Insert into storage.buckets (id, name, public) VALUES ('vendor_logos', 'vendor_logos', true);
-- Insert into storage.buckets (id, name, public) VALUES ('product_images', 'product_images', true);

-- INDEXING --
CREATE INDEX idx_products_vendor ON products(vendor_id);
CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_vendor ON orders(vendor_id);
CREATE INDEX idx_vendors_location ON vendors USING GIST (location);
