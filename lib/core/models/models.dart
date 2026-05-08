import 'package:flutter/foundation.dart';
import '../utils/image_utils.dart';

class SubCategory {
  final String id;
  final String name;
  final String categoryId;
  final int sortOrder;

  SubCategory({
    required this.id,
    required this.name,
    required this.categoryId,
    this.sortOrder = 0,
  });

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    return SubCategory(
      id: json['id'],
      name: json['name'],
      categoryId: json['category_id'],
      sortOrder: json['sort_order'] ?? 0,
    );
  }
}

class MenuCategory {
  final String id;
  final String name;
  final bool isTrending;
  final int sortOrder;
  final List<Product> products;
  final String? imageUrl;
  final List<SubCategory> subCategories;

  MenuCategory({
    required this.id,
    required this.name,
    this.isTrending = false,
    this.sortOrder = 0,
    this.products = const [],
    this.imageUrl,
    this.subCategories = const [],
  });

  factory MenuCategory.fromJson(
    Map<String, dynamic> json,
    List<Product> products, {
    List<SubCategory> subCategories = const [],
  }) {
    return MenuCategory(
      id: json['id'],
      name: json['name'],
      isTrending: json['is_trending'] ?? false,
      sortOrder: json['sort_order'] ?? 0,
      products: products,
      imageUrl: ImageUtils.proxyUrl(json['image_url']),
      subCategories: subCategories,
    );
  }
}

class Vendor {
  final String id;
  final String name;
  final String? logoUrl;
  final String? coverImageUrl;
  final bool isOpen;
  final double deliveryFee;
  final String? estimatedTime;
  final double rating;
  final String? address;
  final int reviewCount;
  final String? openingTime;
  final String? closingTime;
  final String? areaId;
  final double? latitude;
  final double? longitude;
  final bool hasDelivery;
  final bool hasPickup;
  final bool isFreeDelivery;
  final bool isPremium;
  final bool isVisible;
  final bool hasSale;
  final String? areaName; // New field for village name

  // Custom Delivery Overrides
  final bool useCustomDelivery;
  final double? customDeliveryFee;
  final double? freeDeliveryThreshold;


  final int sortOrder;
  final bool isExternalWeb;
  final String? websiteUrl;
  final String? type;
  final bool isBestSelling;
  
  String get formattedEstimatedTime {
    if (estimatedTime == null || estimatedTime!.isEmpty) return "25 د";
    // Extract first number (e.g., from "25-60 min" or "25-60 دقيقة")
    final match = RegExp(r'(\d+)').firstMatch(estimatedTime!);
    if (match != null) {
      return "${match.group(1)} د";
    }
    return estimatedTime!;
  }

  final DateTime? createdAt;
  static int newDurationDays = 7;
  static bool isNewBadgeEnabled = true;
  
  final bool isNewManual;
  
  bool get isNew {
    if (!isNewBadgeEnabled) return false;
    if (isNewManual) return true; // Force ON if manual is true
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt!).inDays <= newDurationDays;
  }

  Vendor({
    required this.id,
    required this.name,
    this.logoUrl,
    this.coverImageUrl,
    required this.isOpen,
    required this.deliveryFee,
    this.estimatedTime,
    required this.rating,
    this.address,
    this.reviewCount = 0,
    this.openingTime,
    this.closingTime,
    this.areaId,
    this.latitude,
    this.longitude,
    this.hasDelivery = true,
    this.hasPickup = false,
    this.isFreeDelivery = false,
    this.isPremium = false,
    this.isVisible = true,
    this.areaName,
    this.type,
    this.isExternalWeb = false,
    this.websiteUrl,
    this.sortOrder = 0,
    this.isBestSelling = false,
    this.hasSale = false,
    this.createdAt,
    this.isNewManual = false,
    this.useCustomDelivery = false,
    this.customDeliveryFee,
    this.freeDeliveryThreshold,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    double? lat;
    double? lng;

    try {
      if (json['location'] != null) {
        final loc = json['location'];
        if (loc is Map && loc['coordinates'] != null && (loc['coordinates'] as List).length >= 2) {
          // GeoJSON format
          lng = (loc['coordinates'][0] as num).toDouble();
          lat = (loc['coordinates'][1] as num).toDouble();
        } else if (loc is String && loc.trim().toUpperCase().startsWith('POINT')) {
          // WKT format: POINT(long lat)
          final parts = loc
              .replaceAll(RegExp(r'POINT\s*\(', caseSensitive: false), '')
              .replaceAll(')', '')
              .trim()
              .split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            lng = double.tryParse(parts[0]);
            lat = double.tryParse(parts[1]);
          }
        }
      }
    } catch (e) {
      debugPrint("Warning: Error parsing vendor location for ${json['id']}: $e");
    }

    return Vendor(
      id: json['id'],
      name: json['name'],
      logoUrl: ImageUtils.proxyUrl(json['logo_url']),
      coverImageUrl: ImageUtils.proxyUrl(json['cover_image_url']),
      isOpen: json['is_open'] ?? true,
      deliveryFee: (json['delivery_fee'] ?? 0).toDouble(),
      estimatedTime: json['estimated_delivery_time'],
      rating: (json['rating_avg'] ?? 0).toDouble(),
      address: json['address'],
      reviewCount: json['review_count'] ?? 10,
      openingTime: json['opening_time'],
      closingTime: json['closing_time'],
      areaId: json['area_id'],
      latitude: lat,
      longitude: lng,
      hasDelivery: json['has_delivery'] ?? true,
      hasPickup: json['has_pickup'] ?? false,
      isFreeDelivery: json['is_free_delivery'] ?? false,
      isPremium: json['is_premium'] ?? false,
      isVisible: json['is_visible'] ?? true,
      type: json['type'],
      isExternalWeb: json['is_external_web'] ?? false,
      websiteUrl: json['website_url'],
      sortOrder: json['sort_order'] ?? 0,
      isBestSelling: json['is_best_selling'] ?? false,
      hasSale: json['has_sale'] ?? false,
      areaName: json['delivery_areas']?['name'],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      isNewManual: json['is_new'] ?? false,
      useCustomDelivery: json['use_custom_delivery'] ?? false,
      customDeliveryFee: json['custom_delivery_fee'] != null ? (json['custom_delivery_fee'] as num).toDouble() : null,
      freeDeliveryThreshold: json['free_delivery_threshold'] != null ? (json['free_delivery_threshold'] as num).toDouble() : null,
    );
  }
}

class Product {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final String vendorId;
  final List<ProductOption> options;
  final bool isTrending;
  final bool isFeatured;

  final int sortOrder;
  final String? subCategory; // Kept for text-based backward compat if needed
  final String? subCategoryId; // FK to sub_categories table
  final double? salePrice;

  Product({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.vendorId,
    this.options = const [],
    this.isTrending = false,
    this.isFeatured = false,
    this.sortOrder = 0,
    this.subCategory,
    this.subCategoryId,
    this.salePrice,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      price: (json['base_price'] ?? 0).toDouble(),
      imageUrl: ImageUtils.proxyUrl(json['image_url']),
      vendorId: json['vendor_id'],
      options:
          (json['options'] as List?)
              ?.map((o) => ProductOption.fromJson(o))
              .toList() ??
          [],
      isTrending: json['is_trending'] ?? false,
      isFeatured: json['is_featured'] ?? false,
      sortOrder: json['sort_order'] ?? 0,
      subCategory: json['sub_category'],
      subCategoryId: json['sub_category_id'],
      salePrice: json['sale_price'] != null ? (json['sale_price'] as num).toDouble() : null,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'base_price': price,
      'image_url': imageUrl,
      'vendor_id': vendorId,
      'options': options.map((o) => o.toJson()).toList(),
      'is_trending': isTrending,
      'is_featured': isFeatured,
      'sort_order': sortOrder,
      'sub_category': subCategory,
      'sub_category_id': subCategoryId,
      'sale_price': salePrice,
    };
  }
}

class ProductOption {
  final String id;
  final String name;
  final bool isRequired;
  final bool isMultiple;
  final String optionType; // 'size', 'single', 'multiple'
  final List<ProductOptionValue> values;

  ProductOption({
    required this.id,
    required this.name,
    required this.isRequired,
    required this.isMultiple,
    this.optionType = 'single',
    this.values = const [],
  });

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    return ProductOption(
      id: json['id'],
      name: json['name'],
      isRequired: json['is_required'] ?? false,
      isMultiple: json['is_multiple'] ?? false,
      optionType: json['option_type'] ?? 'single',
      values:
          (json['values'] as List?)
              ?.map((v) => ProductOptionValue.fromJson(v))
              .toList() ??
          [],
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_required': isRequired,
      'is_multiple': isMultiple,
      'option_type': optionType,
      'values': values.map((v) => v.toJson()).toList(),
    };
  }
}

class ProductOptionValue {
  final String id;
  final String name;
  final double priceModifier;

  ProductOptionValue({
    required this.id,
    required this.name,
    required this.priceModifier,
  });

  factory ProductOptionValue.fromJson(Map<String, dynamic> json) {
    return ProductOptionValue(
      id: json['id'],
      name: json['name'],
      priceModifier: (json['price_modifier'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'price_modifier': priceModifier};
  }
}

class PromotionBanner {
  final String id;
  final String imageUrl;
  final String? areaId;
  final String? dealUrl; // Optional: Link to a specific vendor/product
  final int sortOrder;

  PromotionBanner({
    required this.id,
    required this.imageUrl,
    this.areaId,
    this.dealUrl,
    this.sortOrder = 0,
  });

  factory PromotionBanner.fromJson(Map<String, dynamic> json) {
    return PromotionBanner(
      id: json['id']?.toString() ?? '',
      imageUrl: ImageUtils.proxyUrl(
            (json['image_url'] ?? json['banner_url'] ?? '').toString(),
          ) ??
          '',
      areaId: json['area_id']?.toString(),
      dealUrl: (json['deal_url'] ?? json['link_value'] ?? '').toString(),
      sortOrder: json['sort_order'] ?? 0,
    );
  }

  bool get isVideo {
    final lower = imageUrl.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }
}


class StarPointsTransaction {
  final String id;
  final String userId;
  final int amount;
  final String type;
  final String? description;
  final String? orderId;
  final DateTime createdAt;

  StarPointsTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    this.description,
    this.orderId,
    required this.createdAt,
  });

  factory StarPointsTransaction.fromJson(Map<String, dynamic> json) {
    return StarPointsTransaction(
      id: json['id'],
      userId: json['user_id'],
      amount: json['amount'],
      type: json['type'],
      description: json['description'],
      orderId: json['order_id'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class UserProfile {
  final String id;
  final String? fullName;
  final String? phone;
  final String? role;
  final int starPoints;
  final String? deviceModel;

  UserProfile({
    required this.id,
    this.fullName,
    this.phone,
    this.role,
    this.starPoints = 0,
    this.deviceModel,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      fullName: json['full_name'],
      phone: json['phone'],
      role: json['role'],
      starPoints: json['star_points'] ?? 0,
      deviceModel: json['device_model'],
    );
  }

  dynamic operator [](String key) {
    switch (key) {
      case 'id':
        return id;
      case 'full_name':
        return fullName;
      case 'phone':
        return phone;
      case 'role':
        return role;
      case 'star_points':
        return starPoints;
      default:
        return null;
    }
  }
}

class AppConfig {
  static int homeHorizontalLimit = 20;
}
