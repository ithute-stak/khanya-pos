import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';
import 'package:khanya_pos/features/customers/presentation/bloc/customer_catalog_bloc.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CustomerCatalogBloc(context.read<CustomerRepository>())
        ..add(const CustomerCatalogStarted()),
      child: const _CustomersView(),
    );
  }
}

class _CustomersView extends StatefulWidget {
  const _CustomersView();

  @override
  State<_CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<_CustomersView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addCustomer() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AddCustomerDialog(
        repository: context.read<CustomerRepository>(),
      ),
    );
    if (created == true && mounted) {
      context.read<CustomerCatalogBloc>().add(const CustomerCatalogRefreshRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers & Credit Book'),
        actions: [
          BlocBuilder<CustomerCatalogBloc, CustomerCatalogState>(
            builder: (context, state) => IconButton(
              tooltip: 'Refresh customers',
              onPressed: state.isRefreshing
                  ? null
                  : () => context
                      .read<CustomerCatalogBloc>()
                      .add(const CustomerCatalogRefreshRequested()),
              icon: state.isRefreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
          IconButton(
            tooltip: 'Add customer',
            onPressed: _addCustomer,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: MediaQuery.sizeOf(context).width < 900
          ? FloatingActionButton.extended(
              onPressed: _addCustomer,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add customer'),
            )
          : null,
      body: BlocBuilder<CustomerCatalogBloc, CustomerCatalogState>(
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: () async {
              context.read<CustomerCatalogBloc>().add(const CustomerCatalogRefreshRequested());
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: _CreditSummary(state: state),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => context
                          .read<CustomerCatalogBloc>()
                          .add(CustomerCatalogQueryChanged(value)),
                      decoration: InputDecoration(
                        hintText: 'Search customer, code, phone or email',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  context
                                      .read<CustomerCatalogBloc>()
                                      .add(const CustomerCatalogQueryChanged(''));
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                ),
                if (state.lastError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Material(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_off_outlined, size: 20),
                              const SizedBox(width: 10),
                              Expanded(child: Text(state.lastError!)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (state.visibleCustomers.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.groups_2_outlined, size: 54),
                            const SizedBox(height: 14),
                            Text(
                              state.isRefreshing
                                  ? 'Loading customers…'
                                  : state.query.trim().isEmpty
                                      ? 'No customers yet.'
                                      : 'No customers match your search.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final columns = width >= 1180
                            ? 3
                            : width >= 760
                                ? 2
                                : 1;
                        return SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _CustomerCard(
                              customer: state.visibleCustomers[index],
                            ),
                            childCount: state.visibleCustomers.length,
                          ),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            childAspectRatio: columns == 1 ? 2.15 : 1.8,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                        );
                      },
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

class _CreditSummary extends StatelessWidget {
  const _CreditSummary({required this.state});

  final CustomerCatalogState state;

  @override
  Widget build(BuildContext context) {
    final customersWithBalances = state.customers.where((customer) => customer.outstandingMinor > 0).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final cards = [
          _MetricCard(
            label: 'Customers',
            value: state.customers.length.toString(),
            icon: Icons.groups_2_outlined,
          ),
          _MetricCard(
            label: 'Outstanding credit',
            value: Loti.formatMinor(state.totalOutstandingMinor),
            icon: Icons.account_balance_wallet_outlined,
          ),
          _MetricCard(
            label: 'Owing customers',
            value: customersWithBalances.toString(),
            icon: Icons.receipt_long_outlined,
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (final card in cards) ...[card, const SizedBox(height: 10)],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index != cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final hasDebt = customer.outstandingMinor > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/customers/${customer.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      customer.name.trim().isEmpty ? '?' : customer.name.trim()[0].toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(customer.code, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Icon(
                    hasDebt ? Icons.schedule_outlined : Icons.check_circle_outline,
                    color: hasDebt
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: _AmountLabel(
                      label: 'Outstanding',
                      value: Loti.formatMinor(customer.outstandingMinor),
                    ),
                  ),
                  Expanded(
                    child: _AmountLabel(
                      label: 'Available credit',
                      value: Loti.formatMinor(customer.availableCreditMinor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                customer.creditLimitMinor == 0
                    ? 'Cash customer • no credit limit'
                    : 'Limit ${Loti.formatMinor(customer.creditLimitMinor)} • ${customer.paymentTermsDays} day terms',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountLabel extends StatelessWidget {
  const _AmountLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog({required this.repository});

  final CustomerRepository repository;

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _creditLimit = TextEditingController(text: '0.00');
  final _terms = TextEditingController(text: '0');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _creditLimit.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createCustomer(
        code: _code.text,
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        creditLimitMinor: ScaledDecimal.toMinor(_creditLimit.text),
        paymentTermsDays: int.tryParse(_terms.text.trim()) ?? 0,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Customer could not be created. Check connectivity and customer details.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add customer'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Customer code'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Enter a customer code.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Customer name'),
                  validator: (value) => value == null || value.trim().length < 2 ? 'Enter the customer name.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _creditLimit,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Credit limit (M)'),
                        validator: (value) {
                          final minor = ScaledDecimal.toMinor(value ?? '0');
                          return minor < 0 ? 'Cannot be negative.' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _terms,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Terms (days)'),
                        validator: (value) {
                          final days = int.tryParse(value?.trim() ?? '');
                          if (days == null || days < 0 || days > 365) return 'Use 0–365 days.';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save customer'),
        ),
      ],
    );
  }
}
