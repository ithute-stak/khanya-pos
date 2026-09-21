import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';
import 'package:uuid/uuid.dart';

class PurchasingRepository {
  PurchasingRepository({
    required ApiClient apiClient,
    required AppDatabase database,
    required SessionContext sessionContext,
    required SyncService syncService,
    Uuid? uuid,
  })  : _apiClient = apiClient,
        _database = database,
        _sessionContext = sessionContext,
        _syncService = syncService,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final AppDatabase _database;
  final SessionContext _sessionContext;
  final SyncService _syncService;
  final Uuid _uuid;

  Future<List<SupplierSummary>> listSuppliers() async {
    final tenantId = _requireTenant();
    try {
      final response = await _apiClient.dio.get<List<dynamic>>('/suppliers');
      final suppliers = (response.data ?? const <dynamic>[])
          .map(
            (value) => SupplierSummary.fromJson(
              value as Map<String, dynamic>,
              ScaledDecimal.toMinor,
            ),
          )
          .toList(growable: false);
      final now = DateTime.now().toUtc();
      await _database.replaceSuppliers(
        tenantId: tenantId,
        suppliers: [
          for (final supplier in suppliers)
            CachedSuppliersCompanion.insert(
              supplierId: supplier.id,
              tenantId: tenantId,
              code: supplier.code,
              name: supplier.name,
              phone: Value(supplier.phone),
              email: Value(supplier.email),
              taxNumber: Value(supplier.taxNumber),
              outstandingMinor: Value(supplier.outstandingMinor),
              updatedAt: now,
            ),
        ],
      );
      return suppliers;
    } catch (_) {
      final cached = await _database.getCachedSuppliers(tenantId);
      if (cached.isEmpty) rethrow;
      return cached
          .map(
            (row) => SupplierSummary(
              id: row.supplierId,
              code: row.code,
              name: row.name,
              phone: row.phone,
              email: row.email,
              taxNumber: row.taxNumber,
              outstandingMinor: row.outstandingMinor,
            ),
          )
          .toList(growable: false);
    }
  }

  Future<SupplierSummary> createSupplier({
    required String code,
    required String name,
    String? phone,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/suppliers',
      data: {'code': code.trim(), 'name': name.trim(), 'phone': phone?.trim()},
    );
    final data = response.data!;
    final supplier = SupplierSummary(
      id: data['id'].toString(),
      code: data['code'].toString(),
      name: data['name'].toString(),
      phone: data['phone']?.toString() ?? phone,
      email: data['email']?.toString(),
      taxNumber: data['tax_number']?.toString(),
      outstandingMinor: ScaledDecimal.toMinor(data['outstanding_balance'] ?? 0),
    );
    await listSuppliers();
    return supplier;
  }

  Future<List<PurchaseSummary>> listPurchases() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/purchases');
    return (response.data ?? const <dynamic>[]).map((value) {
      final json = value as Map<String, dynamic>;
      return PurchaseSummary(
        id: json['id'].toString(),
        purchaseNumber: json['purchase_number'].toString(),
        supplierId: json['supplier_id']?.toString(),
        supplierInvoiceNumber: json['supplier_invoice_number']?.toString(),
        purchaseDate: DateTime.tryParse(json['purchase_date']?.toString() ?? '') ?? DateTime.now(),
        status: json['status'].toString(),
        totalMinor: ScaledDecimal.toMinor(json['total']),
        amountPaidMinor: ScaledDecimal.toMinor(json['amount_paid']),
        balanceDueMinor: ScaledDecimal.toMinor(json['balance_due']),
        receiptDocumentId: json['receipt_document_id']?.toString(),
      );
    }).toList(growable: false);
  }

  Future<PurchaseSubmission> receivePurchase({
    required String? supplierId,
    required String? supplierInvoiceNumber,
    required String paymentMethod,
    required int amountPaidMinor,
    required String? receiptDocumentId,
    required String? notes,
    required List<PurchaseDraftLine> lines,
  }) async {
    final tenantId = _requireTenant();
    final branchId = _requireBranch();
    final clientOperationId = _uuid.v4();
    final localDocument = receiptDocumentId == null
        ? null
        : await _database.getPendingDocument(receiptDocumentId);
    final payload = <String, dynamic>{
      'client_operation_id': clientOperationId,
      'supplier_id': supplierId,
      'supplier_invoice_number': supplierInvoiceNumber?.trim().isEmpty == true
          ? null
          : supplierInvoiceNumber?.trim(),
      'payment_method': paymentMethod,
      'amount_paid': ScaledDecimal.fromMinor(amountPaidMinor),
      'receipt_document_id': localDocument == null ? receiptDocumentId : null,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'items': [
        for (final line in lines)
          {
            'product_id': line.product.id,
            'quantity': ScaledDecimal.fromMilli(line.quantityMilli),
            'quantity_received': ScaledDecimal.fromMilli(line.quantityMilli),
            'unit_cost': ScaledDecimal.fromMinor(line.unitCostMinor),
            'tax_total': '0.00',
          },
      ],
    };
    final now = DateTime.now().toUtc();
    await _database.queuePurchaseAndApplyStock(
      purchase: PendingPurchasesCompanion.insert(
        clientOperationId: clientOperationId,
        tenantId: tenantId,
        branchId: branchId,
        payloadJson: jsonEncode(payload),
        localDocumentId: Value(localDocument?.localDocumentId),
        createdAt: now,
        updatedAt: now,
      ),
      tenantId: tenantId,
      branchId: branchId,
      stockChanges: [
        for (final line in lines)
          if (line.product.tracksStock)
            LocalPurchaseStockChange(
              productId: line.product.id,
              quantityMilli: line.quantityMilli,
            ),
      ],
    );

    await _syncService.flushPendingPurchases();
    final pending = await _database.getPendingPurchase(clientOperationId);
    final totalMinor = lines.fold<int>(0, (total, line) => total + line.lineTotalMinor);
    if (pending == null) {
      return PurchaseSubmission(
        id: clientOperationId,
        purchaseNumber: 'Purchase',
        totalMinor: totalMinor,
        balanceDueMinor: totalMinor - amountPaidMinor,
        status: 'synced',
        idempotentReplay: false,
      );
    }
    if (pending.status == 'conflict') {
      throw StateError(pending.lastError ?? 'Purchase needs sync review.');
    }
    return PurchaseSubmission(
      id: clientOperationId,
      purchaseNumber: 'Offline purchase',
      totalMinor: totalMinor,
      balanceDueMinor: totalMinor - amountPaidMinor,
      status: 'queued',
      idempotentReplay: false,
    );
  }

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
