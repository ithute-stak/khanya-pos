import 'package:drift/drift.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';

class ProductRepository {
  ProductRepository({
    required ApiClient apiClient,
    required AppDatabase database,
    required SessionContext sessionContext,
  })  : _apiClient = apiClient,
        _database = database,
        _sessionContext = sessionContext;

  final ApiClient _apiClient;
  final AppDatabase _database;
  final SessionContext _sessionContext;

  Stream<List<ProductSummary>> watchCurrentCatalog() {
    final tenantId = _requireTenant();
    final branchId = _requireBranch();
    return _database
        .watchProducts(tenantId: tenantId, branchId: branchId)
        .map((rows) => rows.map(_fromCached).toList(growable: false));
  }

  Future<List<ProductSummary>> cachedCurrentCatalog() async {
    final rows = await _database.getProducts(
      tenantId: _requireTenant(),
      branchId: _requireBranch(),
    );
    return rows.map(_fromCached).toList(growable: false);
  }

  Future<void> refresh() async {
    final tenantId = _requireTenant();
    final branchId = _requireBranch();
    final response = await _apiClient.dio.get<List<dynamic>>('/products');
    final now = DateTime.now().toUtc();
    final products = (response.data ?? const <dynamic>[]).map((raw) {
      final json = raw as Map<String, dynamic>;
      return CachedProductsCompanion.insert(
        productId: json['id'].toString(),
        tenantId: tenantId,
        branchId: branchId,
        name: json['name'].toString(),
        sku: json['sku'].toString(),
        barcode: Value(json['barcode']?.toString()),
        categoryId: Value(json['category_id']?.toString()),
        unit: Value(json['unit']?.toString() ?? 'unit'),
        sellingPriceMinor: ScaledDecimal.toMinor(json['selling_price']),
        costPriceMinor: ScaledDecimal.toMinor(json['cost_price']),
        onHandMilli: Value(json['on_hand'] == null ? null : ScaledDecimal.toMilli(json['on_hand'])),
        reorderLevelMilli: Value(ScaledDecimal.toMilli(json['reorder_level'])),
        tracksStock: Value(json['track_stock'] as bool? ?? true),
        isLowStock: Value(json['is_low_stock'] as bool? ?? false),
        updatedAt: now,
      );
    });
    await _database.replaceProducts(
      tenantId: tenantId,
      branchId: branchId,
      products: products,
    );
  }

  ProductSummary _fromCached(CachedProduct row) => ProductSummary(
        id: row.productId,
        name: row.name,
        sku: row.sku,
        barcode: row.barcode,
        categoryId: row.categoryId,
        unit: row.unit,
        sellingPriceMinor: row.sellingPriceMinor,
        costPriceMinor: row.costPriceMinor,
        onHandMilli: row.onHandMilli,
        reorderLevelMilli: row.reorderLevelMilli,
        tracksStock: row.tracksStock,
        isLowStock: row.isLowStock,
      );

  String _requireTenant() {
    final value = _sessionContext.tenantId;
    if (value == null) throw StateError('No business selected');
    return value;
  }

  String _requireBranch() {
    final value = _sessionContext.branchId;
    if (value == null) throw StateError('No branch selected');
    return value;
  }
}
