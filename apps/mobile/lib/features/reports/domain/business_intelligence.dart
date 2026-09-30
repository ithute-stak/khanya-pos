import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class BusinessHealthReport extends Equatable {
  const BusinessHealthReport({
    required this.start,
    required this.end,
    required this.overallScore,
    required this.band,
    required this.salesGrowthScore,
    required this.salesGrowthRate,
    required this.profitabilityScore,
    required this.grossMarginRate,
    required this.stockHealthScore,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.customerCreditScore,
    required this.customerCreditMinor,
    required this.expensePressureScore,
    required this.expensesMinor,
    required this.returnsScore,
    required this.returnsMinor,
    required this.grossSalesMinor,
    required this.previousGrossSalesMinor,
    required this.netSalesMinor,
    required this.grossProfitMinor,
    required this.transactions,
  });

  factory BusinessHealthReport.fromJson(Map<String, dynamic> json) {
    final components = (json['components'] as Map<String, dynamic>?) ?? const {};
    final growth = (components['sales_growth'] as Map<String, dynamic>?) ?? const {};
    final profitability = (components['profitability'] as Map<String, dynamic>?) ?? const {};
    final stock = (components['stock_health'] as Map<String, dynamic>?) ?? const {};
    final credit = (components['customer_credit'] as Map<String, dynamic>?) ?? const {};
    final expenses = (components['expense_pressure'] as Map<String, dynamic>?) ?? const {};
    final returns = (components['returns'] as Map<String, dynamic>?) ?? const {};
    final metrics = (json['metrics'] as Map<String, dynamic>?) ?? const {};
    return BusinessHealthReport(
      start: DateTime.parse(json['start'].toString()),
      end: DateTime.parse(json['end'].toString()),
      overallScore: (json['overall_score'] as num?)?.toInt() ?? 0,
      band: json['band']?.toString() ?? 'watch',
      salesGrowthScore: (growth['score'] as num?)?.toInt() ?? 0,
      salesGrowthRate: _double(growth['rate']),
      profitabilityScore: (profitability['score'] as num?)?.toInt() ?? 0,
      grossMarginRate: _double(profitability['gross_margin_rate']),
      stockHealthScore: (stock['score'] as num?)?.toInt() ?? 0,
      lowStockCount: (stock['low_stock_count'] as num?)?.toInt() ?? 0,
      outOfStockCount: (stock['out_of_stock_count'] as num?)?.toInt() ?? 0,
      customerCreditScore: (credit['score'] as num?)?.toInt() ?? 0,
      customerCreditMinor: ScaledDecimal.toMinor(credit['outstanding']),
      expensePressureScore: (expenses['score'] as num?)?.toInt() ?? 0,
      expensesMinor: ScaledDecimal.toMinor(expenses['expenses']),
      returnsScore: (returns['score'] as num?)?.toInt() ?? 0,
      returnsMinor: ScaledDecimal.toMinor(returns['returns_total']),
      grossSalesMinor: ScaledDecimal.toMinor(metrics['gross_sales']),
      previousGrossSalesMinor: ScaledDecimal.toMinor(metrics['previous_gross_sales']),
      netSalesMinor: ScaledDecimal.toMinor(metrics['net_sales']),
      grossProfitMinor: ScaledDecimal.toMinor(metrics['gross_profit']),
      transactions: (metrics['transactions'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime start;
  final DateTime end;
  final int overallScore;
  final String band;
  final int salesGrowthScore;
  final double salesGrowthRate;
  final int profitabilityScore;
  final double grossMarginRate;
  final int stockHealthScore;
  final int lowStockCount;
  final int outOfStockCount;
  final int customerCreditScore;
  final int customerCreditMinor;
  final int expensePressureScore;
  final int expensesMinor;
  final int returnsScore;
  final int returnsMinor;
  final int grossSalesMinor;
  final int previousGrossSalesMinor;
  final int netSalesMinor;
  final int grossProfitMinor;
  final int transactions;

  @override
  List<Object?> get props => [
        start,
        end,
        overallScore,
        band,
        salesGrowthScore,
        salesGrowthRate,
        profitabilityScore,
        grossMarginRate,
        stockHealthScore,
        lowStockCount,
        outOfStockCount,
        customerCreditScore,
        customerCreditMinor,
        expensePressureScore,
        expensesMinor,
        returnsScore,
        returnsMinor,
        grossSalesMinor,
        previousGrossSalesMinor,
        netSalesMinor,
        grossProfitMinor,
        transactions,
      ];
}

class StockIntelligenceReport extends Equatable {
  const StockIntelligenceReport({
    required this.windowDays,
    required this.trackedProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.deadStockCount,
    required this.deadStockCostValueMinor,
    required this.items,
  });

  factory StockIntelligenceReport.fromJson(Map<String, dynamic> json) => StockIntelligenceReport(
        windowDays: (json['window_days'] as num?)?.toInt() ?? 30,
        trackedProducts: (json['tracked_products'] as num?)?.toInt() ?? 0,
        lowStockCount: (json['low_stock_count'] as num?)?.toInt() ?? 0,
        outOfStockCount: (json['out_of_stock_count'] as num?)?.toInt() ?? 0,
        deadStockCount: (json['dead_stock_count'] as num?)?.toInt() ?? 0,
        deadStockCostValueMinor: ScaledDecimal.toMinor(json['dead_stock_cost_value']),
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .map((item) => StockIntelligenceItem.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final int windowDays;
  final int trackedProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final int deadStockCount;
  final int deadStockCostValueMinor;
  final List<StockIntelligenceItem> items;

  @override
  List<Object?> get props => [windowDays, trackedProducts, lowStockCount, outOfStockCount, deadStockCount, deadStockCostValueMinor, items];
}

class StockIntelligenceItem extends Equatable {
  const StockIntelligenceItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.onHandMilli,
    required this.reorderLevelMilli,
    required this.soldQuantityMilli,
    required this.dailyVelocity,
    required this.daysCover,
    required this.suggestedReorderMilli,
    required this.isLowStock,
    required this.isOutOfStock,
    required this.isDeadStock,
    required this.lastSoldAt,
  });

  factory StockIntelligenceItem.fromJson(Map<String, dynamic> json) => StockIntelligenceItem(
        productId: json['product_id'].toString(),
        name: json['name'].toString(),
        sku: json['sku'].toString(),
        onHandMilli: ScaledDecimal.toMilli(json['on_hand']),
        reorderLevelMilli: ScaledDecimal.toMilli(json['reorder_level']),
        soldQuantityMilli: ScaledDecimal.toMilli(json['sold_quantity']),
        dailyVelocity: _double(json['daily_velocity']),
        daysCover: json['days_cover'] == null ? null : _double(json['days_cover']),
        suggestedReorderMilli: ScaledDecimal.toMilli(json['suggested_reorder']),
        isLowStock: json['is_low_stock'] == true,
        isOutOfStock: json['is_out_of_stock'] == true,
        isDeadStock: json['is_dead_stock'] == true,
        lastSoldAt: json['last_sold_at'] == null ? null : DateTime.tryParse(json['last_sold_at'].toString()),
      );

  final String productId;
  final String name;
  final String sku;
  final int onHandMilli;
  final int reorderLevelMilli;
  final int soldQuantityMilli;
  final double dailyVelocity;
  final double? daysCover;
  final int suggestedReorderMilli;
  final bool isLowStock;
  final bool isOutOfStock;
  final bool isDeadStock;
  final DateTime? lastSoldAt;

  @override
  List<Object?> get props => [
        productId,
        name,
        sku,
        onHandMilli,
        reorderLevelMilli,
        soldQuantityMilli,
        dailyVelocity,
        daysCover,
        suggestedReorderMilli,
        isLowStock,
        isOutOfStock,
        isDeadStock,
        lastSoldAt,
      ];
}

class SupplierIntelligenceReport extends Equatable {
  const SupplierIntelligenceReport({
    required this.windowDays,
    required this.supplierCount,
    required this.purchaseTotalMinor,
    required this.outstandingTotalMinor,
    required this.suppliers,
  });

  factory SupplierIntelligenceReport.fromJson(Map<String, dynamic> json) => SupplierIntelligenceReport(
        windowDays: (json['window_days'] as num?)?.toInt() ?? 90,
        supplierCount: (json['supplier_count'] as num?)?.toInt() ?? 0,
        purchaseTotalMinor: ScaledDecimal.toMinor(json['purchase_total']),
        outstandingTotalMinor: ScaledDecimal.toMinor(json['outstanding_total']),
        suppliers: ((json['suppliers'] as List<dynamic>?) ?? const [])
            .map((item) => SupplierInsight.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final int windowDays;
  final int supplierCount;
  final int purchaseTotalMinor;
  final int outstandingTotalMinor;
  final List<SupplierInsight> suppliers;

  @override
  List<Object?> get props => [windowDays, supplierCount, purchaseTotalMinor, outstandingTotalMinor, suppliers];
}

class SupplierInsight extends Equatable {
  const SupplierInsight({
    required this.supplierId,
    required this.name,
    required this.code,
    required this.purchaseCount,
    required this.purchaseTotalMinor,
    required this.outstandingMinor,
    required this.lastPurchaseAt,
  });

  factory SupplierInsight.fromJson(Map<String, dynamic> json) => SupplierInsight(
        supplierId: json['supplier_id'].toString(),
        name: json['name'].toString(),
        code: json['code'].toString(),
        purchaseCount: (json['purchase_count'] as num?)?.toInt() ?? 0,
        purchaseTotalMinor: ScaledDecimal.toMinor(json['purchase_total']),
        outstandingMinor: ScaledDecimal.toMinor(json['outstanding']),
        lastPurchaseAt: json['last_purchase_at'] == null ? null : DateTime.tryParse(json['last_purchase_at'].toString()),
      );

  final String supplierId;
  final String name;
  final String code;
  final int purchaseCount;
  final int purchaseTotalMinor;
  final int outstandingMinor;
  final DateTime? lastPurchaseAt;

  @override
  List<Object?> get props => [supplierId, name, code, purchaseCount, purchaseTotalMinor, outstandingMinor, lastPurchaseAt];
}

double _double(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
