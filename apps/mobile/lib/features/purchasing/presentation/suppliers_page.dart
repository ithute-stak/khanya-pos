import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/presentation/bloc/suppliers_bloc.dart';

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SuppliersBloc(repository: context.read<PurchasingRepository>())
        ..add(const SuppliersRequested()),
      child: const _SuppliersView(),
    );
  }
}

class _SuppliersView extends StatelessWidget {
  const _SuppliersView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersBloc>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.saving ? null : () => _showAddSupplier(context),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add Supplier'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;
          return RefreshIndicator(
            onRefresh: () async {
              context.read<SuppliersBloc>().add(const SuppliersRequested());
              await context.read<SuppliersBloc>().stream.firstWhere((value) => !value.loading);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 100),
              children: [
                if (state.loading) const LinearProgressIndicator(),
                if (state.message != null)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(state.message!)),
                if (!state.loading && state.items.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No suppliers yet.')))
                else
                  ...state.items.map(
                    (supplier) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(supplier.name.characters.first.toUpperCase())),
                        title: Text(supplier.name),
                        subtitle: Text('${supplier.code}${supplier.phone == null ? '' : ' • ${supplier.phone}'}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Outstanding'),
                            Text(
                              Loti.formatMinor(supplier.outstandingMinor),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: supplier.outstandingMinor > 0 ? Theme.of(context).colorScheme.error : null,
                              ),
                            ),
                          ],
                        ),
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

  Future<void> _showAddSupplier(BuildContext context) async {
    final code = TextEditingController();
    final name = TextEditingController();
    final phone = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add supplier'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'Supplier code')),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Supplier name')),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    if (submitted == true && context.mounted && code.text.trim().isNotEmpty && name.text.trim().length >= 2) {
      context.read<SuppliersBloc>().add(
            SupplierCreateRequested(
              code: code.text,
              name: name.text,
              phone: phone.text.trim().isEmpty ? null : phone.text,
            ),
          );
    }
    code.dispose();
    name.dispose();
    phone.dispose();
  }
}
