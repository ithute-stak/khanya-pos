import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';
import 'package:uuid/uuid.dart';

class PurchasingRepository {
  PurchasingRepository({required ApiClient apiClient, Uuid? uuid})
      : _apiClient = apiClient,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final Uuid _uuid;

  Future<List<SupplierSummary>> listSuppliers() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/suppliers');
    return (response.data ?? const <dynamic>[])
        .map(
          (value) => SupplierSummary.fromJson(
            value as Map<String, dynamic>,
            ScaledDecimal.toMinor,
          ),
        )
        .toList(growable: false);
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
    return SupplierSummary(
      id: data['id'].toString(),
      code: data['code'].toString(),
      name: data['name'].toString(),
      phone: phone,
      outstandingMinor: 0,
    );
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
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/purchases/receive',
      data: {
        'client_operation_id': _uuid.v4(),
        'supplier_id': supplierId,
        'supplier_invoice_number': supplierInvoiceNumber?.trim().isEmpty == true
            ? null
            : supplierInvoiceNumber?.trim(),
        'payment_method': paymentMethod,
        'amount_paid': ScaledDecimal.fromMinor(amountPaidMinor),
        'receipt_document_id': receiptDocumentId,
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
      },
    );
    final data = response.data!;
    return PurchaseSubmission(
      id: data['id'].toString(),
      purchaseNumber: data['purchase_number'].toString(),
      totalMinor: ScaledDecimal.toMinor(data['total']),
      balanceDueMinor: ScaledDecimal.toMinor(data['balance_due']),
      status: data['status'].toString(),
      idempotentReplay: data['idempotent_replay'] as bool? ?? false,
    );
  }
}
