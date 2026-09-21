import 'package:equatable/equatable.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';

class SupplierSummary extends Equatable {
  const SupplierSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.outstandingMinor,
    this.phone,
    this.email,
    this.taxNumber,
  });

  factory SupplierSummary.fromJson(Map<String, dynamic> json, int Function(dynamic) moneyParser) {
    return SupplierSummary(
      id: json['id'].toString(),
      code: json['code'].toString(),
      name: json['name'].toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      taxNumber: json['tax_number']?.toString(),
      outstandingMinor: moneyParser(json['outstanding_balance']),
    );
  }

  final String id;
  final String code;
  final String name;
  final String? phone;
  final String? email;
  final String? taxNumber;
  final int outstandingMinor;

  @override
  List<Object?> get props => [id, code, name, phone, email, taxNumber, outstandingMinor];
}

class PurchaseSummary extends Equatable {
  const PurchaseSummary({
    required this.id,
    required this.purchaseNumber,
    required this.purchaseDate,
    required this.status,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.balanceDueMinor,
    this.supplierId,
    this.supplierInvoiceNumber,
    this.receiptDocumentId,
  });

  final String id;
  final String purchaseNumber;
  final String? supplierId;
  final String? supplierInvoiceNumber;
  final DateTime purchaseDate;
  final String status;
  final int totalMinor;
  final int amountPaidMinor;
  final int balanceDueMinor;
  final String? receiptDocumentId;

  @override
  List<Object?> get props => [
        id,
        purchaseNumber,
        supplierId,
        supplierInvoiceNumber,
        purchaseDate,
        status,
        totalMinor,
        amountPaidMinor,
        balanceDueMinor,
        receiptDocumentId,
      ];
}

class PurchaseDraftLine extends Equatable {
  const PurchaseDraftLine({
    required this.product,
    required this.quantityMilli,
    required this.unitCostMinor,
  });

  final ProductSummary product;
  final int quantityMilli;
  final int unitCostMinor;

  int get lineTotalMinor => ((unitCostMinor * quantityMilli) + 500) ~/ 1000;

  PurchaseDraftLine copyWith({int? quantityMilli, int? unitCostMinor}) => PurchaseDraftLine(
        product: product,
        quantityMilli: quantityMilli ?? this.quantityMilli,
        unitCostMinor: unitCostMinor ?? this.unitCostMinor,
      );

  @override
  List<Object?> get props => [product, quantityMilli, unitCostMinor];
}

class PurchaseSubmission extends Equatable {
  const PurchaseSubmission({
    required this.id,
    required this.purchaseNumber,
    required this.totalMinor,
    required this.balanceDueMinor,
    required this.status,
    required this.idempotentReplay,
  });

  final String id;
  final String purchaseNumber;
  final int totalMinor;
  final int balanceDueMinor;
  final String status;
  final bool idempotentReplay;

  @override
  List<Object?> get props => [id, purchaseNumber, totalMinor, balanceDueMinor, status, idempotentReplay];
}
