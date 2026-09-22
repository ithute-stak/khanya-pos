import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class CashFlowActivity extends Equatable {
  const CashFlowActivity({
    required this.entryNumber,
    required this.occurredAt,
    required this.description,
    required this.sourceType,
    required this.category,
    required this.amountMinor,
  });

  factory CashFlowActivity.fromJson(Map<String, dynamic> json) => CashFlowActivity(
        entryNumber: json['entry_number']?.toString() ?? '',
        occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        description: json['description']?.toString() ?? '',
        sourceType: json['source_type']?.toString() ?? '',
        category: json['category']?.toString() ?? 'operating',
        amountMinor: ScaledDecimal.toMinor(json['amount']),
      );

  final String entryNumber;
  final DateTime occurredAt;
  final String description;
  final String sourceType;
  final String category;
  final int amountMinor;

  @override
  List<Object?> get props => [
        entryNumber,
        occurredAt,
        description,
        sourceType,
        category,
        amountMinor,
      ];
}

class CashFlowReport extends Equatable {
  const CashFlowReport({
    required this.openingCashMinor,
    required this.operatingCashFlowMinor,
    required this.investingCashFlowMinor,
    required this.financingCashFlowMinor,
    required this.netChangeInCashMinor,
    required this.closingCashMinor,
    required this.expectedClosingCashMinor,
    required this.differenceMinor,
    required this.activities,
  });

  factory CashFlowReport.fromJson(Map<String, dynamic> json) => CashFlowReport(
        openingCashMinor: ScaledDecimal.toMinor(json['opening_cash']),
        operatingCashFlowMinor: ScaledDecimal.toMinor(json['operating_cash_flow']),
        investingCashFlowMinor: ScaledDecimal.toMinor(json['investing_cash_flow']),
        financingCashFlowMinor: ScaledDecimal.toMinor(json['financing_cash_flow']),
        netChangeInCashMinor: ScaledDecimal.toMinor(json['net_change_in_cash']),
        closingCashMinor: ScaledDecimal.toMinor(json['closing_cash']),
        expectedClosingCashMinor: ScaledDecimal.toMinor(json['expected_closing_cash']),
        differenceMinor: ScaledDecimal.toMinor(json['difference']),
        activities: (json['activities'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => CashFlowActivity.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final int openingCashMinor;
  final int operatingCashFlowMinor;
  final int investingCashFlowMinor;
  final int financingCashFlowMinor;
  final int netChangeInCashMinor;
  final int closingCashMinor;
  final int expectedClosingCashMinor;
  final int differenceMinor;
  final List<CashFlowActivity> activities;

  bool get reconciles => differenceMinor == 0;

  @override
  List<Object?> get props => [
        openingCashMinor,
        operatingCashFlowMinor,
        investingCashFlowMinor,
        financingCashFlowMinor,
        netChangeInCashMinor,
        closingCashMinor,
        expectedClosingCashMinor,
        differenceMinor,
        activities,
      ];
}
