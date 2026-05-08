-- SUPABASE RLS POLICIES (SECURITY LAYER)

-- 1. Profiles
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Profiles are viewable by everyone" ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can update only their own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

-- 2. Vendors
ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Vendors are viewable by everyone" ON vendors FOR SELECT USING (true);
CREATE POLICY "Vendors can manage their own data" ON vendors FOR ALL USING (auth.uid() = owner_id);

-- 3. Categories
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Categories are viewable by everyone" ON categories FOR SELECT USING (true);
CREATE POLICY "Vendors manage their own categories" ON categories FOR ALL 
USING (EXISTS (SELECT 1 FROM vendors WHERE id = categories.vendor_id AND owner_id = auth.uid()));

-- 4. Products
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Products are viewable by everyone" ON products FOR SELECT USING (true);
CREATE POLICY "Vendors manage their own products" ON products FOR ALL 
USING (EXISTS (SELECT 1 FROM vendors WHERE id = products.vendor_id AND owner_id = auth.uid()));

-- 5. Carts
ALTER TABLE carts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own cart" ON carts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create their own cart" ON carts FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 6. Cart Items
ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage their own cart items" ON cart_items FOR ALL 
USING (EXISTS (SELECT 1 FROM carts WHERE id = cart_items.cart_id AND user_id = auth.uid()));

-- 7. Orders
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Customers view their own orders" ON orders FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Customers can place orders" ON orders FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Vendors view orders for their shop" ON orders FOR SELECT 
USING (EXISTS (SELECT 1 FROM vendors WHERE id = orders.vendor_id AND owner_id = auth.uid()));
CREATE POLICY "Drivers view assigned orders" ON orders FOR SELECT USING (auth.uid() = driver_id);

-- 8. Order Items
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "View items if allowed to view the order" ON order_items FOR SELECT 
USING (EXISTS (SELECT 1 FROM orders WHERE id = order_items.order_id));

-- 9. Drivers
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view active drivers" ON drivers FOR SELECT USING (is_available = true);
CREATE POLICY "Drivers manage their own profile" ON drivers FOR ALL USING (auth.uid() = profile_id);

-- 10. Notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view only their own notifications" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users update read status" ON notifications FOR UPDATE USING (auth.uid() = user_id);
