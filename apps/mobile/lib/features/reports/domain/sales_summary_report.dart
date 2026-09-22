import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class SalesSummaryReport extends Equatable {
  const SalesSummaryReport({
    required this.start,
    required this.end,
    required this.saleCount,
    required this.grossSalesMinor,
    required this.returnsTotalMinor,
    required this.netSalesMinor,
    required this.taxTotalMinor,
    required this.balanceDueMinor,
    required this.costOfGoodsMinor,
    required this.grossProfitMinor,
    required this.returnCount,
    required this.refundedAmountMinor,
    required this.payments,
    required this.topProducts,
  });

  factory SalesSummaryReport.fromJson(Map<String, dynamic> json) => SalesSummaryReport(
        start: DateTime.parse(json['start'].toString()),
        end: DateTime.parse(json['end'].toString()),
        saleCount: (json['sale_count'] as num?)?.toInt() ?? 0,
        grossSalesMinor: ScaledDecimal.toMinor(json['gross_sales']),
        returnsTotalMinor: ScaledDecimal.toMinor(json['returns_total']),
        netSalesMinor: ScaledDecimal.toMinor(json['net_sales']),
        taxTotalMinor: ScaledDecimal.toMinor(json['tax_total']),
        balanceDueMinor: ScaledDecimal.toMinor(json['balance_due']),
        costOfGoodsMinor: ScaledDecimal.toMinor(json['cost_of_goods']),
        grossProfitMinor: ScaledDecimal.toMinor(json['gross_profit']),
        returnCount: (json['return_count'] as num?)?.toInt() ?? 0,
        refundedAmountMinor: ScaledDecimal.toMinor(json['refunded_amount']),
        payments: ((json['payments'] as List<dynamic>?) ?? const [])
            .map((item) => PaymentSummary.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        topProducts: ((json['top_products'] as List<dynamic>?) ?? const [])
            .map((item) => TopProductSummary.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final DateTime start;
  final DateTime end;
  final int saleCount;
  final int grossSalesMinor;
  final int returnsTotalMinor;
  final int netSalesMinor;
  final int taxTotalMinor;
  final int balanceDueMinor;
  final int costOfGoodsMinor;
  final int grossProfitMinor;
  final int returnCount;
  final int refundedAmountMinor;
  final List<PaymentSummary> payments;
  final List<TopProductSummary> topProducts;

  @override
  List<Object?> get props => [
        start,
        end,
        saleCount,
        grossSalesMinor,
        returnsTotalMinor,
        netSalesMinor,
        taxTotalMinor,
        balanceDueMinor,
        costOfGoodsMinor,
        grossProfitMinor,
        returnCount,
        refundedAmountMinor,
        payments,
        topProducts,
      ];
}

class PaymentSummary extends Equatable {
  const PaymentSummary({required this.method, required this.amountMinor});

  factory PaymentSummary.fromJson(Map<String, dynamic> json) => PaymentSummary(
        method: json['method'].toString(),
        amountMinor: ScaledDecimal.toMinor(json['amount']),
      );

  final String method;
  final int amountMinor;

  @override
  List<Object?> get props => [method, amountMinor];
}

class TopProductSummary extends Equatable {
  const TopProductSummary({
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantityMilli,
    required this.revenueMinor,
  });

  factory TopProductSummary.fromJson(Map<String, dynamic> json) => TopProductSummary(
        productId: json['product_id'].toString(),
        name: json['name'].toString(),
        sku: json['sku'].toString(),
        quantityMilli: ScaledDecimal.toMilli(json['quantity']),
        revenueMinor: ScaledDecimal.toMinor(json['revenue']),
      );

  final String productId;
  final String name;
  final String sku;
  final int quantityMilli;
  final int revenueMinor;

  @override
  List<Object?> get props => [productId, name, sku, quantityMilli, revenueMinor];
}
