import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:uuid/uuid.dart';

class InventoryBranch {
  const InventoryBranch({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory InventoryBranch.fromJson(Map<String, dynamic> json) => InventoryBranch(
        id: json['id'].toString(),
        name: json['name'].toString(),
        code: json['code'].toString(),
      );
}

class InventoryMovementSummary {
  const InventoryMovementSummary({
    required this.id,
    required this.productName,
    required this.sku,
    required this.movementType,
    required this.quantityMilli,
    required this.occurredAt,
    this.reason,
  });

  final String id;
  final String productName;
  final String sku;
  final String movementType;
  final int quantityMilli;
  final DateTime occurredAt;
  final String? reason;

  factory InventoryMovementSummary.fromJson(Map<String, dynamic> json) => InventoryMovementSummary(
        id: json['id'].toString(),
        productName: json['product_name'].toString(),
        sku: json['sku'].toString(),
        movementType: json['movement_type'].toString(),
        quantityMilli: ScaledDecimal.toMilli(json['quantity_delta']),
        occurredAt: DateTime.parse(json['occurred_at'].toString()).toLocal(),
        reason: json['reason']?.toString(),
      );
}

class InventoryControlRepository {
  InventoryControlRepository({
    required ApiClient apiClient,
    required SessionContext sessionContext,
    Uuid? uuid,
  })  : _apiClient = apiClient,
        _sessionContext = sessionContext,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final SessionContext _sessionContext;
  final Uuid _uuid;

  Future<List<InventoryBranch>> branches() async {
    _requireTenant();
    final currentBranchId = _requireBranch();
    final response = await _apiClient.dio.get<List<dynamic>>('/tenants/current/branches');
    return (response.data ?? const [])
        .map((row) => InventoryBranch.fromJson((row as Map).cast<String, dynamic>()))
        .where((branch) => branch.id != currentBranchId)
        .toList(growable: false);
  }

  Future<void> transfer({
    required String destinationBranchId,
    required String reason,
    required Map<String, int> productQuantitiesMilli,
    String? reference,
  }) async {
    final currentBranchId = _requireBranch();
    if (destinationBranchId == currentBranchId) throw StateError('Choose a different destination branch.');
    if (productQuantitiesMilli.isEmpty) throw StateError('Choose at least one product to transfer.');
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/inventory/transfers',
      data: {
        'client_operation_id': _uuid.v4(),
        'destination_branch_id': destinationBranchId,
        'reference': _blankToNull(reference),
        'reason': reason.trim(),
        'lines': [
          for (final entry in productQuantitiesMilli.entries)
            {
              'product_id': entry.key,
              'quantity': ScaledDecimal.fromMilli(entry.value),
            },
        ],
      },
    );
  }

  Future<void> stocktake({
    required String reason,
    required Map<String, int> countedQuantitiesMilli,
    String? reference,
  }) async {
    _requireBranch();
    if (countedQuantitiesMilli.isEmpty) throw StateError('Enter at least one physical count.');
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/inventory/stocktakes',
      data: {
        'client_operation_id': _uuid.v4(),
        'reference': _blankToNull(reference),
        'reason': reason.trim(),
        'lines': [
          for (final entry in countedQuantitiesMilli.entries)
            {
              'product_id': entry.key,
              'counted_quantity': ScaledDecimal.fromMilli(entry.value),
            },
        ],
      },
    );
  }

  Future<void> adjust({
    required String productId,
    required int quantityDeltaMilli,
    required String adjustmentType,
    required String reason,
  }) async {
    _requireBranch();
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/inventory/adjustments',
      data: {
        'client_operation_id': _uuid.v4(),
        'product_id': productId,
        'quantity_delta': ScaledDecimal.fromMilli(quantityDeltaMilli),
        'adjustment_type': adjustmentType,
        'reason': reason.trim(),
      },
    );
  }

  Future<List<InventoryMovementSummary>> movements({String? productId}) async {
    _requireBranch();
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/inventory/movements',
      queryParameters: {if (productId != null) 'product_id': productId, 'limit': 150},
    );
    return (response.data ?? const [])
        .map((row) => InventoryMovementSummary.fromJson((row as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  String _requireTenant() {
    final tenant = _sessionContext.tenantId;
    if (tenant == null) throw StateError('Select a business first.');
    return tenant;
  }

  String _requireBranch() {
    final branch = _sessionContext.branchId;
    if (branch == null) throw StateError('Select a branch first.');
    return branch;
  }

  String? _blankToNull(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
