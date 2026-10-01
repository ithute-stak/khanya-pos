import 'package:dio/dio.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';

class PromotionSummary {
  const PromotionSummary({
    required this.id,
    required this.name,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minSubtotal,
    required this.useCount,
    required this.isActive,
    required this.currentlyAvailable,
    this.maxUses,
    this.startsAt,
    this.endsAt,
  });

  factory PromotionSummary.fromJson(Map<String, dynamic> json) => PromotionSummary(
        id: json['id'].toString(),
        name: json['name'].toString(),
        code: json['code'].toString(),
        discountType: json['discount_type'].toString(),
        discountValue: json['discount_value'].toString(),
        minSubtotal: json['min_subtotal'].toString(),
        useCount: (json['use_count'] as num?)?.toInt() ?? 0,
        maxUses: (json['max_uses'] as num?)?.toInt(),
        isActive: json['is_active'] == true,
        currentlyAvailable: json['currently_available'] == true,
        startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
        endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? ''),
      );

  final String id;
  final String name;
  final String code;
  final String discountType;
  final String discountValue;
  final String minSubtotal;
  final int useCount;
  final int? maxUses;
  final bool isActive;
  final bool currentlyAvailable;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

class LoyaltyProgramSummary {
  const LoyaltyProgramSummary({
    required this.name,
    required this.isActive,
    required this.pointsPerCurrency,
    required this.currencyPerPoint,
    required this.minRedeemPoints,
  });

  factory LoyaltyProgramSummary.fromJson(Map<String, dynamic> json) => LoyaltyProgramSummary(
        name: json['name']?.toString() ?? 'Khanya Rewards',
        isActive: json['is_active'] == true,
        pointsPerCurrency: json['points_per_currency']?.toString() ?? '1.0000',
        currencyPerPoint: json['currency_per_point']?.toString() ?? '0.0100',
        minRedeemPoints: (json['min_redeem_points'] as num?)?.toInt() ?? 100,
      );

  final String name;
  final bool isActive;
  final String pointsPerCurrency;
  final String currencyPerPoint;
  final int minRedeemPoints;
}

class LoyaltyCustomerSummary {
  const LoyaltyCustomerSummary({
    required this.customerId,
    required this.customerName,
    required this.pointsBalance,
    required this.lifetimeEarned,
    required this.lifetimeRedeemed,
  });

  factory LoyaltyCustomerSummary.fromJson(Map<String, dynamic> json) => LoyaltyCustomerSummary(
        customerId: json['customer_id'].toString(),
        customerName: json['customer_name'].toString(),
        pointsBalance: (json['points_balance'] as num?)?.toInt() ?? 0,
        lifetimeEarned: (json['lifetime_earned'] as num?)?.toInt() ?? 0,
        lifetimeRedeemed: (json['lifetime_redeemed'] as num?)?.toInt() ?? 0,
      );

  final String customerId;
  final String customerName;
  final int pointsBalance;
  final int lifetimeEarned;
  final int lifetimeRedeemed;
}

class PromotionPreview {
  const PromotionPreview({required this.discountMinor, required this.totalMinor});
  factory PromotionPreview.fromJson(Map<String, dynamic> json) => PromotionPreview(
        discountMinor: ScaledDecimal.parseMoneyMinor(json['discount']?.toString() ?? '0'),
        totalMinor: ScaledDecimal.parseMoneyMinor(json['total_after_discount']?.toString() ?? '0'),
      );

  final int discountMinor;
  final int totalMinor;
}

class GrowthRepository {
  GrowthRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<List<PromotionSummary>> promotions() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/growth/promotions');
    return (response.data ?? const <dynamic>[])
        .map((item) => PromotionSummary.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> createPromotion({
    required String name,
    required String code,
    required String discountType,
    required String discountValue,
    String minSubtotal = '0',
    int? maxUses,
    bool isActive = true,
  }) async {
    await _apiClient.dio.post<void>(
      '/growth/promotions',
      data: {
        'name': name.trim(),
        'code': code.trim(),
        'discount_type': discountType,
        'discount_value': discountValue,
        'min_subtotal': minSubtotal,
        'max_uses': maxUses,
        'is_active': isActive,
      },
    );
  }

  Future<PromotionPreview> previewPromotion({required String code, required int subtotalMinor}) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/growth/promotions/preview',
        data: {
          'code': code.trim(),
          'subtotal': ScaledDecimal.fromMinor(subtotalMinor),
        },
      );
      return PromotionPreview.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (error) {
      throw StateError(_message(error, 'Promotion could not be applied.'));
    }
  }

  Future<LoyaltyProgramSummary> loyaltyProgram() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/growth/loyalty/program');
    return LoyaltyProgramSummary.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<void> saveLoyaltyProgram({
    required String name,
    required bool isActive,
    required String pointsPerCurrency,
    required String currencyPerPoint,
    required int minRedeemPoints,
  }) async {
    await _apiClient.dio.put<void>(
      '/growth/loyalty/program',
      data: {
        'name': name.trim(),
        'is_active': isActive,
        'points_per_currency': pointsPerCurrency,
        'currency_per_point': currencyPerPoint,
        'min_redeem_points': minRedeemPoints,
      },
    );
  }

  Future<LoyaltyCustomerSummary> customerLoyalty(String customerId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/growth/loyalty/customers/$customerId');
    return LoyaltyCustomerSummary.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> alerts() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/growth/alerts');
    return response.data ?? const <String, dynamic>{};
  }

  String _message(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    return fallback;
  }
}
