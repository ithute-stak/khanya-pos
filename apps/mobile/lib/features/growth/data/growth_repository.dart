import 'package:khanya_pos/core/network/api_client.dart';

class GrowthRepository {
  GrowthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Map<String, dynamic>>> promotions() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/growth/promotions');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> createPromotion({
    required String code,
    required String name,
    required String discountType,
    required double discountValue,
    String? productId,
    double minimumQuantity = 1,
    required DateTime startsAt,
    DateTime? endsAt,
    bool isActive = true,
  }) async {
    await _apiClient.dio.post<void>(
      '/growth/promotions',
      data: <String, dynamic>{
        'code': code,
        'name': name,
        'discount_type': discountType,
        'discount_value': discountValue,
        'product_id': productId,
        'minimum_quantity': minimumQuantity,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'is_active': isActive,
      },
    );
  }

  Future<void> updatePromotion({
    required String id,
    required String code,
    required String name,
    required String discountType,
    required double discountValue,
    String? productId,
    double minimumQuantity = 1,
    required DateTime startsAt,
    DateTime? endsAt,
    bool isActive = true,
  }) async {
    await _apiClient.dio.patch<void>(
      '/growth/promotions/$id',
      data: <String, dynamic>{
        'code': code,
        'name': name,
        'discount_type': discountType,
        'discount_value': discountValue,
        'product_id': productId,
        'minimum_quantity': minimumQuantity,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'is_active': isActive,
      },
    );
  }

  Future<Map<String, dynamic>> loyaltyProgram() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/growth/loyalty/program');
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> setLoyaltyProgram({
    required bool enabled,
    required double pointsPerCurrency,
    required double redemptionValue,
    required int minimumRedeemPoints,
  }) async {
    await _apiClient.dio.put<void>(
      '/growth/loyalty/program',
      data: <String, dynamic>{
        'enabled': enabled,
        'points_per_currency': pointsPerCurrency,
        'redemption_value': redemptionValue,
        'minimum_redeem_points': minimumRedeemPoints,
      },
    );
  }

  Future<Map<String, dynamic>> customerLoyalty(String customerId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/growth/loyalty/customers/$customerId');
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> adjustCustomerLoyalty({
    required String customerId,
    required int pointsDelta,
    required String note,
  }) async {
    await _apiClient.dio.post<void>(
      '/growth/loyalty/customers/$customerId/adjust',
      data: <String, dynamic>{'points_delta': pointsDelta, 'note': note},
    );
  }
}
