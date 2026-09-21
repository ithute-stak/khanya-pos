import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/expenses/domain/expense_summary.dart';
import 'package:uuid/uuid.dart';

class ExpenseRepository {
  ExpenseRepository({required ApiClient apiClient, Uuid? uuid})
      : _apiClient = apiClient,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final Uuid _uuid;

  Future<List<ExpenseSummary>> listExpenses() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/expenses');
    return (response.data ?? const <dynamic>[]).map((value) {
      final json = value as Map<String, dynamic>;
      return ExpenseSummary(
        id: json['id'].toString(),
        expenseNumber: json['expense_number'].toString(),
        category: json['category'].toString(),
        description: json['description'].toString(),
        amountMinor: ScaledDecimal.toMinor(json['amount']),
        paymentMethod: json['payment_method'].toString(),
        expenseDate: DateTime.tryParse(json['expense_date']?.toString() ?? '') ?? DateTime.now(),
        receiptDocumentId: json['receipt_document_id']?.toString(),
      );
    }).toList(growable: false);
  }

  Future<void> createExpense({
    required String category,
    required String description,
    required int amountMinor,
    required String paymentMethod,
    String? receiptDocumentId,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/expenses',
      data: {
        'client_operation_id': _uuid.v4(),
        'category': category,
        'description': description.trim(),
        'amount': ScaledDecimal.fromMinor(amountMinor),
        'payment_method': paymentMethod,
        'receipt_document_id': receiptDocumentId,
      },
    );
  }
}
