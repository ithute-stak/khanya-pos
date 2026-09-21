import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/features/documents/data/document_repository.dart';
import 'package:khanya_pos/features/documents/data/receipt_picker.dart';
import 'package:khanya_pos/features/documents/presentation/bloc/receipt_capture_bloc.dart';
import 'package:khanya_pos/features/documents/presentation/receipt_capture_buttons.dart';
import 'package:khanya_pos/features/expenses/data/expense_repository.dart';
import 'package:khanya_pos/features/expenses/presentation/bloc/expenses_bloc.dart';

class AddExpensePage extends StatelessWidget {
  const AddExpensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ExpensesBloc(repository: context.read<ExpenseRepository>())),
        BlocProvider(create: (_) => ReceiptCaptureBloc(repository: context.read<DocumentRepository>())),
      ],
      child: const _AddExpenseView(),
    );
  }
}

class _AddExpenseView extends StatefulWidget {
  const _AddExpenseView();

  @override
  State<_AddExpenseView> createState() => _AddExpenseViewState();
}

class _AddExpenseViewState extends State<_AddExpenseView> {
  static const categories = [
    'rent',
    'electricity',
    'water',
    'transport',
    'fuel',
    'airtime',
    'mobile_data',
    'internet',
    'bank_charges',
    'mobile_money_charges',
    'stationery',
    'packaging',
    'repairs',
    'security',
    'wages',
    'licences',
    'advertising',
    'equipment',
    'professional_services',
    'other',
  ];

  final description = TextEditingController();
  final amount = TextEditingController();
  String category = 'electricity';
  String paymentMethod = 'cash';

  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = context.watch<ReceiptCaptureBloc>().state.selected;
    final expenseState = context.watch<ExpensesBloc>().state;
    return BlocListener<ExpensesBloc, ExpensesState>(
      listenWhen: (previous, current) => !previous.saved && current.saved,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense saved.')));
        context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Expense')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;
            return ListView(
              padding: EdgeInsets.all(padding),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: category,
                                  decoration: const InputDecoration(labelText: 'Expense category'),
                                  items: categories
                                      .map((value) => DropdownMenuItem(value: value, child: Text(value.replaceAll('_', ' '))))
                                      .toList(),
                                  onChanged: (value) => setState(() => category = value ?? category),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: description,
                                  decoration: const InputDecoration(labelText: 'Description'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: amount,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Amount (M)'),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: paymentMethod,
                                  decoration: const InputDecoration(labelText: 'Payment method'),
                                  items: const [
                                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                    DropdownMenuItem(value: 'card', child: Text('Card')),
                                    DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money')),
                                    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                                  ],
                                  onChanged: (value) => setState(() => paymentMethod = value ?? paymentMethod),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Supporting receipt', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 6),
                                const Text('Attach the fuel slip, electricity receipt, invoice or other proof of this expense.'),
                                const SizedBox(height: 14),
                                const ReceiptCaptureButtons(purpose: ReceiptPurpose.expense),
                              ],
                            ),
                          ),
                        ),
                        if (expenseState.message != null) ...[
                          const SizedBox(height: 12),
                          Text(expenseState.message!),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: expenseState.saving
                                ? null
                                : () => context.read<ExpensesBloc>().add(
                                      ExpenseCreateRequested(
                                        category: category,
                                        description: description.text,
                                        amountText: amount.text,
                                        paymentMethod: paymentMethod,
                                        receiptDocumentId: receipt?.id,
                                      ),
                                    ),
                            icon: expenseState.saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.save_outlined),
                            label: Text(expenseState.saving ? 'Saving...' : 'Save Expense'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
