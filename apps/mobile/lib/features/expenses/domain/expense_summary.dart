import 'package:equatable/equatable.dart';

class ExpenseSummary extends Equatable {
  const ExpenseSummary({
    required this.id,
    required this.expenseNumber,
    required this.category,
    required this.description,
    required this.amountMinor,
    required this.paymentMethod,
    required this.expenseDate,
    this.receiptDocumentId,
  });

  final String id;
  final String expenseNumber;
  final String category;
  final String description;
  final int amountMinor;
  final String paymentMethod;
  final DateTime expenseDate;
  final String? receiptDocumentId;

  @override
  List<Object?> get props => [
        id,
        expenseNumber,
        category,
        description,
        amountMinor,
        paymentMethod,
        expenseDate,
        receiptDocumentId,
      ];
}
