import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class TillShiftSummary extends Equatable {
  const TillShiftSummary({
    required this.id,
    required this.status,
    required this.openingFloatMinor,
    required this.openedAt,
    required this.cashSalesMinor,
    required this.cashSaleCount,
    required this.paidInMinor,
    required this.paidOutMinor,
    required this.expectedCashMinor,
    this.closingCashCountedMinor,
    this.varianceMinor,
    this.closingNote,
    this.closedAt,
  });

  factory TillShiftSummary.fromJson(Map<String, dynamic> json) => TillShiftSummary(
        id: json['id'].toString(),
        status: json['status'].toString(),
        openingFloatMinor: ScaledDecimal.toMinor(json['opening_float']),
        openedAt: DateTime.parse(json['opened_at'].toString()),
        cashSalesMinor: ScaledDecimal.toMinor(json['cash_sales']),
        cashSaleCount: (json['cash_sale_count'] as num?)?.toInt() ?? 0,
        paidInMinor: ScaledDecimal.toMinor(json['paid_in']),
        paidOutMinor: ScaledDecimal.toMinor(json['paid_out']),
        expectedCashMinor: ScaledDecimal.toMinor(json['expected_cash']),
        closingCashCountedMinor: json['closing_cash_counted'] == null
            ? null
            : ScaledDecimal.toMinor(json['closing_cash_counted']),
        varianceMinor: json['variance'] == null ? null : ScaledDecimal.toMinor(json['variance']),
        closingNote: json['closing_note']?.toString(),
        closedAt: json['closed_at'] == null ? null : DateTime.tryParse(json['closed_at'].toString()),
      );

  final String id;
  final String status;
  final int openingFloatMinor;
  final DateTime openedAt;
  final int cashSalesMinor;
  final int cashSaleCount;
  final int paidInMinor;
  final int paidOutMinor;
  final int expectedCashMinor;
  final int? closingCashCountedMinor;
  final int? varianceMinor;
  final String? closingNote;
  final DateTime? closedAt;

  bool get isOpen => status == 'open';

  @override
  List<Object?> get props => [
        id,
        status,
        openingFloatMinor,
        openedAt,
        cashSalesMinor,
        cashSaleCount,
        paidInMinor,
        paidOutMinor,
        expectedCashMinor,
        closingCashCountedMinor,
        varianceMinor,
        closingNote,
        closedAt,
      ];
}
