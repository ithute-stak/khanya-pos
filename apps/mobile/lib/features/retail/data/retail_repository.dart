import 'package:dio/dio.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:uuid/uuid.dart';

class RetailRepository {
  RetailRepository({required ApiClient apiClient, Uuid? uuid})
      : _apiClient = apiClient,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final Uuid _uuid;

  Future<List<Map<String, dynamic>>> promotions({bool activeOnly = false}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/retail/promotions',
      queryParameters: {'active_only': activeOnly},
    );
    return (response.data ?? const <dynamic>[])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
  }

  Future<void> createPromotion({
    required String name,
    required String code,
    required String discountType,
    required String discountValue,
    String minimumSubtotal = '0.00',
    DateTime? startsAt,
    DateTime? endsAt,
    int? usageLimit,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/retail/promotions',
      data: {
        'name': name.trim(),
        'code': code.trim(),
        'discount_type': discountType,
        'discount_value': discountValue.trim(),
        'minimum_subtotal': minimumSubtotal.trim(),
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'usage_limit': usageLimit,
        'is_active': true,
      },
    );
  }

  Future<void> setPromotionActive(String promotionId, bool active) async {
    await _apiClient.dio.patch<Map<String, dynamic>>(
      '/retail/promotions/$promotionId',
      data: {'is_active': active},
    );
  }

  Future<Map<String, dynamic>> loyaltyProgram() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/retail/loyalty/program');
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> updateLoyaltyProgram({
    required bool active,
    required String spendPerPoint,
    required String redemptionValuePerPoint,
    required int minimumRedeemPoints,
  }) async {
    await _apiClient.dio.put<Map<String, dynamic>>(
      '/retail/loyalty/program',
      data: {
        'is_active': active,
        'spend_per_point': spendPerPoint.trim(),
        'redemption_value_per_point': redemptionValuePerPoint.trim(),
        'minimum_redeem_points': minimumRedeemPoints,
      },
    );
  }

  Future<Map<String, dynamic>> customerLoyalty(String customerId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/retail/loyalty/customers/$customerId',
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> previewCheckoutBenefits({
    required int subtotalMinor,
    String? customerId,
    String? promotionCode,
    int loyaltyPointsToRedeem = 0,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/retail/checkout/preview',
      data: {
        'subtotal': ScaledDecimal.fromMinor(subtotalMinor),
        'customer_id': customerId,
        'promotion_code': _nullableText(promotionCode),
        'loyalty_points_to_redeem': loyaltyPointsToRedeem,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> adjustLoyalty({
    required String customerId,
    required int pointsDelta,
    required String reason,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/retail/loyalty/customers/$customerId/adjust',
      data: {'points_delta': pointsDelta, 'reason': reason.trim()},
    );
  }

  Future<List<Map<String, dynamic>>> purchaseOrders({String? status}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/retail/purchase-orders',
      queryParameters: {'status': ?status},
    );
    return (response.data ?? const <dynamic>[])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createPurchaseOrder({
    required String supplierId,
    required List<({ProductSummary product, int quantityMilli, int unitCostMinor})> lines,
    DateTime? expectedDate,
    String? notes,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/retail/purchase-orders',
      data: {
        'client_operation_id': _uuid.v4(),
        'supplier_id': supplierId,
        'expected_date': expectedDate?.toUtc().toIso8601String(),
        'notes': _nullableText(notes),
        'items': [
          for (final line in lines)
            {
              'product_id': line.product.id,
              'quantity': ScaledDecimal.fromMilli(line.quantityMilli),
              'unit_cost': ScaledDecimal.fromMinor(line.unitCostMinor),
              'tax_total': '0.00',
            },
        ],
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> transitionPurchaseOrder(String orderId, String action) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/retail/purchase-orders/$orderId/$action',
    );
  }

  Future<void> receivePurchaseOrder({
    required String orderId,
    String paymentMethod = 'supplier_credit',
    int amountPaidMinor = 0,
    String? supplierInvoiceNumber,
    String? notes,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/retail/purchase-orders/$orderId/receive',
      data: {
        'client_operation_id': _uuid.v4(),
        'supplier_invoice_number': _nullableText(supplierInvoiceNumber),
        'payment_method': paymentMethod,
        'amount_paid': ScaledDecimal.fromMinor(amountPaidMinor),
        'notes': _nullableText(notes),
      },
    );
  }

  Future<List<Map<String, dynamic>>> labelPreview({
    required List<String> productIds,
    int copies = 1,
    bool includePrice = true,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/retail/labels/preview',
      data: {
        'product_ids': productIds,
        'copies': copies,
        'include_price': includePrice,
      },
    );
    return ((response.data?['labels'] as List<dynamic>?) ?? const <dynamic>[])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> notifications({bool unreadOnly = false}) async {
    final responses = await Future.wait([
      _apiClient.dio.get<List<dynamic>>(
        '/retail/notifications',
        queryParameters: {'unread_only': unreadOnly, 'limit': 100},
      ),
      _apiClient.dio.get<List<dynamic>>('/retail/alerts'),
    ]);
    final persistent = (responses[0].data ?? const <dynamic>[])
        .map((value) => Map<String, dynamic>.from(value as Map));
    final alerts = (responses[1].data ?? const <dynamic>[])
        .map((value) => Map<String, dynamic>.from(value as Map));
    final combined = <Map<String, dynamic>>[...alerts, ...persistent];
    if (!unreadOnly) return combined;
    return combined.where((item) => item['read_at'] == null).toList(growable: false);
  }

  Future<void> markNotificationRead(String notificationId) async {
    if (notificationId.contains(':')) return;
    await _apiClient.dio.post<Map<String, dynamic>>('/retail/notifications/$notificationId/read');
  }

  String? _nullableText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String errorMessage(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) return data['detail'].toString();
    }
    return fallback;
  }
}
