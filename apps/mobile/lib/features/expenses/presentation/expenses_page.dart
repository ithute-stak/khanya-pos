import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/expenses/data/expense_repository.dart';
import 'package:khanya_pos/features/expenses/presentation/bloc/expenses_bloc.dart';

class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ExpensesBloc(repository: context.read<ExpenseRepository>())
        ..add(const ExpensesRequested()),
      child: const _ExpensesView(),
    );
  }
}

class _ExpensesView extends StatelessWidget {
  const _ExpensesView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ExpensesBloc>().state;
    final total = state.items.fold<int>(0, (sum, expense) => sum + expense.amountMinor);
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/expenses/new');
          if (context.mounted) context.read<ExpensesBloc>().add(const ExpensesRequested());
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;
          return RefreshIndicator(
            onRefresh: () async {
              context.read<ExpensesBloc>().add(const ExpensesRequested());
              await context.read<ExpensesBloc>().stream.firstWhere((value) => !value.loading);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 100),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Recorded expenses'),
                            Text(Loti.formatMinor(total), style: Theme.of(context).textTheme.headlineSmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (state.loading) const LinearProgressIndicator(),
                if (!state.loading && state.items.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No expenses recorded yet.')))
                else
                  ...state.items.map(
                    (expense) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
                        title: Text(expense.description),
                        subtitle: Text(
                          '${expense.category.replaceAll('_', ' ')} • ${expense.paymentMethod.replaceAll('_', ' ')}\n'
                          '${expense.expenseDate.toLocal().toString().substring(0, 10)}',
                        ),
                        isThreeLine: true,
                        trailing: Text(Loti.formatMinor(expense.amountMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
