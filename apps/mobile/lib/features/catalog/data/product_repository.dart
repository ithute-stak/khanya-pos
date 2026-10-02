import 'package:drift/drift.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';

class CatalogMasterItem {
  const CatalogMasterItem({required this.id, required this.name});

  final String id;
  final String name;

  factory CatalogMasterItem.fromJson(Map<String, dynamic> json) => CatalogMasterItem(
        id: json['id'].toString(),
        name: json['name'].toString(),
      );
}

class ProductDetail {
  const ProductDetail({
    required this.id,
    required this.name,
    required this.sku,
    required this.unit,
    required this.sellingPriceMinor,
    required this.costPriceMinor,
    required this.reorderLevelMilli,
    required this.tracksStock,
    required this.isActive,
    required this.isLowStock,
    this.barcode,
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brandName,
    this.unitId,
    this.unitName,
    this.onHandMilli,
  });

  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final String? brandId;
  final String? brandName;
  final String? unitId;
  final String? unitName;
  final String unit;
  final int sellingPriceMinor;
  final int costPriceMinor;
  final int reorderLevelMilli;
  final int? onHandMilli;
  final bool tracksStock;
  final bool isActive;
  final bool isLowStock;

  factory ProductDetail.fromJson(Map<String, dynamic> json) => ProductDetail(
        id: json['id'].toString(),
        name: json['name'].toString(),
        sku: json['sku'].toString(),
        barcode: json['barcode']?.toString(),
        categoryId: json['category_id']?.toString(),
        categoryName: json['category_name']?.toString(),
        brandId: json['brand_id']?.toString(),
        brandName: json['brand_name']?.toString(),
        unitId: json['unit_id']?.toString(),
        unitName: json['unit_name']?.toString(),
        unit: json['unit']?.toString() ?? 'unit',
        sellingPriceMinor: ScaledDecimal.toMinor(json['selling_price']),
        costPriceMinor: ScaledDecimal.toMinor(json['cost_price']),
        reorderLevelMilli: ScaledDecimal.toMilli(json['reorder_level']),
        onHandMilli: json['on_hand'] == null ? null : ScaledDecimal.toMilli(json['on_hand']),
        tracksStock: json['track_stock'] as bool? ?? true,
        isActive: json['is_active'] as bool? ?? true,
        isLowStock: json['is_low_stock'] as bool? ?? false,
      );
}

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

  Future<void> createProduct({
    required String name,
    required String sku,
    String? barcode,
    String? categoryId,
    String? brandId,
    String? unitId,
    required String unit,
    required String sellingPrice,
    required String costPrice,
    required String reorderLevel,
    required bool trackStock,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/products',
      data: <String, dynamic>{
        'name': name.trim(),
        'sku': sku.trim(),
        'barcode': barcode?.trim().isEmpty ?? true ? null : barcode!.trim(),
        'category_id': categoryId,
        'brand_id': brandId,
        'unit_id': unitId,
        'unit': unit.trim(),
        'selling_price': sellingPrice.trim(),
        'cost_price': costPrice.trim(),
        'reorder_level': reorderLevel.trim(),
        'track_stock': trackStock,
      },
    );
    await refresh();
  }

  Future<ProductDetail> productDetail(String productId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/products/$productId');
    return ProductDetail.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<void> updateProduct({
    required String productId,
    required String name,
    required String sku,
    String? barcode,
    String? categoryId,
    String? brandId,
    String? unitId,
    required String unit,
    required String sellingPrice,
    required String costPrice,
    required String reorderLevel,
    required bool trackStock,
    bool isActive = true,
  }) async {
    await _apiClient.dio.put<Map<String, dynamic>>(
      '/products/$productId',
      data: <String, dynamic>{
        'name': name.trim(),
        'sku': sku.trim(),
        'barcode': barcode?.trim().isEmpty ?? true ? null : barcode!.trim(),
        'category_id': categoryId,
        'brand_id': brandId,
        'unit_id': unitId,
        'unit': unit.trim(),
        'selling_price': sellingPrice.trim(),
        'cost_price': costPrice.trim(),
        'reorder_level': reorderLevel.trim(),
        'track_stock': trackStock,
        'is_active': isActive,
      },
    );
    await refresh();
  }

  Future<List<CatalogMasterItem>> categories() => _masterList('/products/categories');

  Future<List<CatalogMasterItem>> brands() => _masterList('/products/brands');

  Future<List<CatalogMasterItem>> units() => _masterList('/products/units');

  Future<CatalogMasterItem> createCategory(String name) =>
      _createMaster('/products/categories', name);

  Future<CatalogMasterItem> createBrand(String name) =>
      _createMaster('/products/brands', name);

  Future<CatalogMasterItem> createUnit(String name) =>
      _createMaster('/products/units', name);

  Future<List<CatalogMasterItem>> _masterList(String path) async {
    final response = await _apiClient.dio.get<List<dynamic>>(path);
    return (response.data ?? const <dynamic>[])
        .map((row) => CatalogMasterItem.fromJson((row as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<CatalogMasterItem> _createMaster(String path, String name) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      path,
      data: {'name': name.trim()},
    );
    return CatalogMasterItem.fromJson(response.data ?? const <String, dynamic>{});
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
