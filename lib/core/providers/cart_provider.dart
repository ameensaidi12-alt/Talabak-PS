import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];
  final _client = Supabase.instance.client;
  RealtimeChannel? _cartChannel;

  CartProvider() {
    _init();
  }

  Future<void> _init() async {
    // 1. Ensure local cart is loaded BEFORE anything else
    await _loadLocally();
    _initAuthListener();
  }

  void _initAuthListener() {
    // 2. Listen to Auth Changes
    _client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        // User logged in: Sync with Supabase
        loadFromSupabase();
        _subscribeToCartChanges();
      } else {
        // User logged out: Unsubscribe but KEEP local cart (persistence)
        _cartChannel?.unsubscribe();
        _cartChannel = null;
        // We do legacy behavior: clearAll(localOnly: true) if you want to clear on logout.
        // But user asked for persistence. Usually, on explicit logout, we clear.
        // For now, we'll keep it to match "don't lose items when app closes".
        // If user explicitly logs out, they usually expect clear.
        // But here we are handling "AuthStateChange", which happens on app start too.
        // So we should NOT clear if it's just an initial "no session" state.
      }
    });
  }

  void _subscribeToCartChanges() {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // Cancel existing subscription if any
    _cartChannel?.unsubscribe();

    _cartChannel = _client
        .channel('cart_changes_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'web_cart_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint(
              '🛒 [CartProvider] Realtime cart change: ${payload.eventType}',
            );
            loadFromSupabase(); // This will also update local storage
          },
        )
        .subscribe();
  }

  // --- Local Persistence Methods ---

  Future<void> _saveLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded = jsonEncode(
        _items.map((item) => item.toJson()).toList(),
      );
      await prefs.setString('local_cart_items', encoded);
    } catch (e) {
      debugPrint("❌ Error saving cart locally: $e");
    }
  }

  Future<void> _loadLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? encoded = prefs.getString('local_cart_items');
      if (encoded != null) {
        final List<dynamic> decoded = jsonDecode(encoded);
        _items.clear();
        _items.addAll(decoded.map((x) => CartItem.fromJson(x)));
        notifyListeners();
      }
    } catch (e) {
      debugPrint("❌ Error loading cart locally: $e");
    }
  }

  // --- Supabase Methods ---

  Future<void> loadFromSupabase() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Push any local items that haven't been synced yet
      final toSync = _items.where((i) => i.id == null).toList();
      if (toSync.isNotEmpty) {
        for (var item in toSync) {
          await _syncLocalItemToSupabase(item, user.id);
        }
      }

      // 2. Fetch remote cart
      final response = await _client
          .from('web_cart_items')
          .select('*, products:web_products(*)')
          .eq('user_id', user.id);

      final List<dynamic> data = response;

      // 3. Smart Merge: Keep track of existing product IDs to avoid duplicates
      final List<CartItem> remoteItems = [];
      for (var item in data) {
        remoteItems.add(
          CartItem(
            id: item['id'].toString(),
            product: _productFromWebJson(item['products']),
            quantity: item['quantity'],
            vendorName: '',
            notes: item['notes'],
            selectedOptions: _parseWebAddons(item['selected_addons']),
          ),
        );
      }

      // If remote has data, it becomes the source of truth, 
      // but we keep local items that are still "unsynced" (though we pushed them above, 
      // they might not be in the fetch result yet due to timing)
      _items.clear();
      _items.addAll(remoteItems);
      
      notifyListeners();
      _saveLocally();
    } catch (e) {
      debugPrint("❌ Error loading cart from Supabase: $e");
    }
  }

  Future<void> _syncLocalItemToSupabase(CartItem item, String userId) async {
    try {
      await _client.from('web_cart_items').insert({
        'user_id': userId,
        'product_id': item.product.id,
        'vendor_id': item.product.vendorId,
        'quantity': item.quantity,
        'notes': item.notes,
        'selected_addons': item.selectedOptions
            .map((o) => {
                  ...o.value.toJson(),
                  'quantity': o.quantity,
                  'price': o.value.priceModifier,
                })
            .toList(),
        'source': 'mob_app_sync',
      });
    } catch (e) {
      debugPrint("❌ Error syncing local item to Supabase: $e");
    }
  }

  List<CartItem> get items => List.unmodifiable(_items);

  int get totalItemsCount {
    int count = 0;
    for (var item in _items) {
      count += item.quantity;
    }
    return count;
  }

  Product _productFromWebJson(Map<String, dynamic> json) {
    final double? promoPrice = json['promo_price'] != null ? (json['promo_price'] as num).toDouble() : null;
    final double basePrice = (json['price'] ?? 0 as num).toDouble();
    
    return Product(
      id: json['id'],
      name: json['name_ar'] ?? json['name'] ?? '',
      description: json['description_ar'] ?? json['description'],
      price: basePrice,
      salePrice: promoPrice,
      imageUrl: json['image_url'],
      vendorId: json['vendor_id'],
      isFeatured: json['is_featured'] ?? false,
    );
  }

  List<SelectedAddon> _parseWebAddons(dynamic addons) {
    if (addons == null) return [];
    try {
      final List<dynamic> list = addons is List ? addons : [];
      return list.map((a) {
        final map = a as Map<String, dynamic>;
        return SelectedAddon(
          value: ProductOptionValue(
            id: map['id']?.toString() ?? '',
            name: map['name_ar'] ?? map['name'] ?? '',
            priceModifier: (map['price'] ?? 0).toDouble(),
          ),
          quantity: map['quantity'] ?? 1,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Error parsing addons: $e');
      return [];
    }
  }

  double get totalPrice {
    double total = 0;
    for (var item in _items) {
      total += item.totalPrice;
    }
    return (total * 100).roundToDouble() / 100;
  }

  double get totalWithFees => totalPrice;

  Map<String, List<CartItem>> get itemsByVendor {
    final Map<String, List<CartItem>> grouped = {};
    for (var item in _items) {
      grouped.putIfAbsent(item.product.vendorId, () => []).add(item);
    }
    return grouped;
  }

  void addItem(
    Product product,
    int quantity,
    String vendorName, {
    String? notes,
    List<SelectedAddon> selectedOptions = const [],
  }) async {
    final user = _client.auth.currentUser;

    final index = _items.indexWhere((i) {
      if (i.product.id != product.id) return false;
      if (i.selectedOptions.length != selectedOptions.length) return false;
      
      // Compare selected addons by ID and Quantity
      final selectedMap = {for (var o in selectedOptions) o.value.id: o.quantity};
      final itemMap = {for (var o in i.selectedOptions) o.value.id: o.quantity};
      
      if (selectedMap.length != itemMap.length) return false;
      for (var key in selectedMap.keys) {
        if (selectedMap[key] != itemMap[key]) return false;
      }
      return true;
    });

    if (index >= 0) {
      _items[index].quantity += quantity;
      if (user != null) {
        try {
          await _client
              .from('web_cart_items')
              .update({'quantity': _items[index].quantity})
              .eq('id', _items[index].id!);
        } catch (e) {
          debugPrint("Error updating remote cart: $e");
        }
      }
    } else {
      final newItem = CartItem(
        product: product,
        quantity: quantity,
        vendorName: vendorName,
        notes: notes,
        selectedOptions: selectedOptions,
      );
      _items.add(newItem);

      if (user != null) {
        try {
          final res = await _client
              .from('web_cart_items')
              .insert({
                'user_id': user.id,
                'product_id': product.id,
                'vendor_id': product.vendorId,
                'quantity': quantity,
                'notes': notes,
                'selected_addons': selectedOptions
                    .map((o) => {
                          ...o.value.toJson(),
                          'quantity': o.quantity,
                          'price': o.value.priceModifier, // for legacy compat
                        })
                    .toList(),
                'source': 'mob_app',
              })
              .select()
              .single();

          final idx = _items.indexOf(newItem);
          if (idx != -1) {
            _items[idx] = CartItem(
              id: res['id'].toString(),
              product: newItem.product,
              quantity: newItem.quantity,
              vendorName: newItem.vendorName,
              notes: newItem.notes,
              selectedOptions: newItem.selectedOptions,
            );
          }
        } catch (e) {
          debugPrint("Error adding to remote cart: $e");
        }
      }
    }

    notifyListeners();
    _saveLocally();
  }

  void removeItem(String cartItemId) async {
    final user = _client.auth.currentUser;
    final index = _items.indexWhere(
      (i) => i.id == cartItemId || i.product.id == cartItemId,
    );

    String? dbId;
    String? productId;

    if (index != -1) {
      dbId = _items[index].id;
      productId = _items[index].product.id;
      _items.removeAt(index);
    } else {
      _items.removeWhere(
        (i) => i.id == cartItemId || i.product.id == cartItemId,
      );
    }
    notifyListeners();
    _saveLocally();

    if (user != null) {
      try {
        if (dbId != null) {
          await _client.from('web_cart_items').delete().eq('id', dbId);
        } else if (productId != null) {
          await _client
              .from('web_cart_items')
              .delete()
              .eq('user_id', user.id)
              .eq('product_id', productId);
        } else {
          await _client.from('web_cart_items').delete().eq('id', cartItemId);
        }
      } catch (e) {
        debugPrint("Error deleting from remote cart: $e");
      }
    }
  }

  void updateQuantity(String cartItemId, int newQuantity) async {
    if (newQuantity <= 0) {
      removeItem(cartItemId);
      return;
    }

    final index = _items.indexWhere((i) => i.id == cartItemId || i.product.id == cartItemId);
    if (index != -1) {
      _items[index].quantity = newQuantity;
      notifyListeners();
      _saveLocally();

      final user = _client.auth.currentUser;
      if (user != null) {
        try {
          final id = _items[index].id;
          if (id != null) {
            await _client.from('web_cart_items').update({'quantity': newQuantity}).eq('id', id);
          }
        } catch (e) {
          debugPrint("Error updating remote quantity: $e");
        }
      }
    }
  }

  void clearAll({bool localOnly = false}) async {
    _items.clear();
    _saveLocally();

    if (!localOnly) {
      final user = _client.auth.currentUser;
      if (user != null) {
        try {
          await _client.from('web_cart_items').delete().eq('user_id', user.id);
        } catch (e) {
          debugPrint("Error clearing remote cart: $e");
        }
      }
    }
    notifyListeners();
  }
}

class SelectedAddon {
  final ProductOptionValue value;
  final int quantity;

  SelectedAddon({required this.value, this.quantity = 1});

  Map<String, dynamic> toJson() {
    return {
      'value': value.toJson(),
      'quantity': quantity,
    };
  }

  factory SelectedAddon.fromJson(Map<String, dynamic> json) {
    return SelectedAddon(
      value: ProductOptionValue.fromJson(json['value']),
      quantity: json['quantity'] ?? 1,
    );
  }
}

class CartItem {
  final String? id;
  final Product product;
  final String vendorName;
  final String? notes;
  final List<SelectedAddon> selectedOptions;
  int quantity;

  CartItem({
    this.id,
    required this.product,
    required this.quantity,
    required this.vendorName,
    this.notes,
    this.selectedOptions = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'quantity': quantity,
      'vendor_name': vendorName,
      'notes': notes,
      'selected_options': selectedOptions.map((o) => o.toJson()).toList(),
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      product: Product.fromJson(json['product']),
      quantity: json['quantity'] ?? 1,
      vendorName: json['vendor_name'] ?? '',
      notes: json['notes'],
      selectedOptions: (json['selected_options'] as List?)
              ?.map((o) => SelectedAddon.fromJson(o))
              .toList() ??
          [],
    );
  }

  double get unitPrice {
    double total = product.salePrice ?? product.price;
    for (var opt in selectedOptions) {
      total += (opt.value.priceModifier * opt.quantity);
    }
    return (total * 100).roundToDouble() / 100;
  }

  double get totalPrice => ((unitPrice * quantity) * 100).roundToDouble() / 100;
}
