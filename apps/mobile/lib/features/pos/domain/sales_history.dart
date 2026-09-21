import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class SaleHistoryEntry extends Equatable {
  const SaleHistoryEntry({
    required this.id,
    required this.saleNumber,
    required this.totalMinor,
    required this.balanceDueMinor,
    required this.paymentStatus,
    required this.completedAt,
    required this.returnedTotalMinor,
    required this.returnStatus,
    required this.refundableTotalMinor,
  });

  factory SaleHistoryEntry.fromJson(Map<String, dynamic> json) => SaleHistoryEntry(
        id: json['id'].toString(),
        saleNumber: json['sale_number'].toString(),
        totalMinor: ScaledDecimal.toMinor(json['total']),
        balanceDueMinor: ScaledDecimal.toMinor(json['balance_due']),
        paymentStatus: json['payment_status'].toString(),
        completedAt: DateTime.parse(json['completed_at'].toString()),
        returnedTotalMinor: ScaledDecimal.toMinor(json['returned_total']),
        returnStatus: json['return_status'].toString(),
        refundableTotalMinor: ScaledDecimal.toMinor(json['refundable_total']),
      );

  final String id;
  final String saleNumber;
  final int totalMinor;
  final int balanceDueMinor;
  final String paymentStatus;
  final DateTime completedAt;
  final int returnedTotalMinor;
  final String returnStatus;
  final int refundableTotalMinor;

  bool get hasReturns => returnedTotalMinor > 0;
  bool get fullyReturned => returnStatus == 'full' || refundableTotalMinor <= 0;

  @override
  List<Object?> get props => [
        id,
        saleNumber,
        totalMinor,
        balanceDueMinor,
        paymentStatus,
        completedAt,
        returnedTotalMinor,
        returnStatus,
        refundableTotalMinor,
      ];
}

class SaleLineDetail extends Equatable {
  const SaleLineDetail({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantityMilli,
    required this.returnedQuantityMilli,
    required this.returnableQuantityMilli,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.returnedTotalMinor,
  });

  factory SaleLineDetail.fromJson(Map<String, dynamic> json) => SaleLineDetail(
        id: json['id'].toString(),
        productId: json['product_id'].toString(),
        productName: json['product_name'].toString(),
        sku: json['sku'].toString(),
        quantityMilli: ScaledDecimal.toMilli(json['quantity']),
        returnedQuantityMilli: ScaledDecimal.toMilli(json['returned_quantity']),
        returnableQuantityMilli: ScaledDecimal.toMilli(json['returnable_quantity']),
        unitPriceMinor: ScaledDecimal.toMinor(json['unit_price']),
        lineTotalMinor: ScaledDecimal.toMinor(json['line_total']),
        returnedTotalMinor: ScaledDecimal.toMinor(json['returned_total']),
      );

  final String id;
  final String productId;
  final String productName;
  final String sku;
  final int quantityMilli;
  final int returnedQuantityMilli;
  final int returnableQuantityMilli;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final int returnedTotalMinor;

  bool get canReturn => returnableQuantityMilli > 0;

  @override
  List<Object?> get props => [
        id,
        productId,
        productName,
        sku,
        quantityMilli,
        returnedQuantityMilli,
        returnableQuantityMilli,
        unitPriceMinor,
        lineTotalMinor,
        returnedTotalMinor,
      ];
}

class SalePaymentRecord extends Equatable {
  const SalePaymentRecord({
    required this.method,
    required this.amountMinor,
    this.reference,
  });

  factory SalePaymentRecord.fromJson(Map<String, dynamic> json) => SalePaymentRecord(
        method: json['method'].toString(),
        amountMinor: ScaledDecimal.toMinor(json['amount']),
        reference: json['reference']?.toString(),
      );

  final String method;
  final int amountMinor;
  final String? reference;

  @override
  List<Object?> get props => [method, amountMinor, reference];
}

class SaleReturnRecord extends Equatable {
  const SaleReturnRecord({
    required this.id,
    required this.returnNumber,
    required this.kind,
    required this.reason,
    required this.totalMinor,
    required this.receivableReductionMinor,
    required this.refundedAmountMinor,
    required this.processedAt,
    this.refundMethod,
    this.refundReference,
  });

  factory SaleReturnRecord.fromJson(Map<String, dynamic> json) => SaleReturnRecord(
        id: json['id'].toString(),
        returnNumber: json['return_number'].toString(),
        kind: json['kind'].toString(),
        reason: json['reason'].toString(),
        totalMinor: ScaledDecimal.toMinor(json['total']),
        receivableReductionMinor: ScaledDecimal.toMinor(json['receivable_reduction']),
        refundedAmountMinor: ScaledDecimal.toMinor(json['refunded_amount']),
        refundMethod: json['refund_method']?.toString(),
        refundReference: json['refund_reference']?.toString(),
        processedAt: DateTime.parse(json['processed_at'].toString()),
      );

  final String id;
  final String returnNumber;
  final String kind;
  final String reason;
  final int totalMinor;
  final int receivableReductionMinor;
  final int refundedAmountMinor;
  final String? refundMethod;
  final String? refundReference;
  final DateTime processedAt;

  @override
  List<Object?> get props => [
        id,
        returnNumber,
        kind,
        reason,
        totalMinor,
        receivableReductionMinor,
        refundedAmountMinor,
        refundMethod,
        refundReference,
        processedAt,
      ];
}

class SaleDetail extends Equatable {
  const SaleDetail({
    required this.id,
    required this.saleNumber,
    required this.totalMinor,
    required this.balanceDueMinor,
    required this.paymentStatus,
    required this.completedAt,
    required this.returnedTotalMinor,
    required this.refundableTotalMinor,
    required this.returnStatus,
    required this.lines,
    required this.payments,
    required this.returns,
  });

  factory SaleDetail.fromJson(Map<String, dynamic> json) => SaleDetail(
        id: json['id'].toString(),
        saleNumber: json['sale_number'].toString(),
        totalMinor: ScaledDecimal.toMinor(json['total']),
        balanceDueMinor: ScaledDecimal.toMinor(json['balance_due']),
        paymentStatus: json['payment_status'].toString(),
        completedAt: DateTime.parse(json['completed_at'].toString()),
        returnedTotalMinor: ScaledDecimal.toMinor(json['returned_total']),
        refundableTotalMinor: ScaledDecimal.toMinor(json['refundable_total']),
        returnStatus: json['return_status'].toString(),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .map((value) => SaleLineDetail.fromJson(Map<String, dynamic>.from(value as Map)))
            .toList(growable: false),
        payments: (json['payments'] as List<dynamic>? ?? const [])
            .map((value) => SalePaymentRecord.fromJson(Map<String, dynamic>.from(value as Map)))
            .toList(growable: false),
        returns: (json['returns'] as List<dynamic>? ?? const [])
            .map((value) => SaleReturnRecord.fromJson(Map<String, dynamic>.from(value as Map)))
            .toList(growable: false),
      );

  final String id;
  final String saleNumber;
  final int totalMinor;
  final int balanceDueMinor;
  final String paymentStatus;
  final DateTime completedAt;
  final int returnedTotalMinor;
  final int refundableTotalMinor;
  final String returnStatus;
  final List<SaleLineDetail> lines;
  final List<SalePaymentRecord> payments;
  final List<SaleReturnRecord> returns;

  bool get fullyReturned => returnStatus == 'full' || refundableTotalMinor <= 0;

  @override
  List<Object?> get props => [
        id,
        saleNumber,
        totalMinor,
        balanceDueMinor,
        paymentStatus,
        completedAt,
        returnedTotalMinor,
        refundableTotalMinor,
        returnStatus,
        lines,
        payments,
        returns,
      ];
}
