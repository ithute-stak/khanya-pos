import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/services/data/service_repository.dart';

/// First-stage service checkout: records confirmed cash payments only.
/// Card/mobile-money authorization and offline queuing require later integration.
class ServiceCheckoutPage extends StatefulWidget {
  const ServiceCheckoutPage({super.key});
  @override
  State<ServiceCheckoutPage> createState() => _ServiceCheckoutPageState();
}

class _ServiceCheckoutPageState extends State<ServiceCheckoutPage> {
  late Future<List<ServiceEntry>> _services;
  ServiceEntry? _selected;
  int _quantity = 1;
  bool _submitting = false;
  String? _confirmation;
  String? _pendingOperationId;
  String? _pendingServiceId;
  int? _pendingQuantity;
  String? _pendingAmount;
  bool _statusUnknown = false;

  @override
  void initState() {
    super.initState();
    _services = context.read<ServiceRepository>().list();
  }

  Future<void> _checkout() async {
    final service = _selected;
    if (service == null || _submitting) return;
    final price = double.tryParse(service.price);
    if (price == null) return;
    final amount = (price * _quantity).toStringAsFixed(2);
    if (_pendingOperationId != null &&
        (_pendingServiceId != service.id || _pendingQuantity != _quantity || _pendingAmount != amount)) {
      return;
    }
    final confirmed = _pendingOperationId == null ? await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm cash received'),
        content: Text('Record cash payment of M $amount for $_quantity × ${service.name}? Only confirm after receiving the cash.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cash received')),
        ],
      ),
    ) : true;
    if (confirmed != true || !mounted) return;
    _pendingOperationId ??= ServiceRepository.newOperationId();
    _pendingServiceId ??= service.id;
    _pendingQuantity ??= _quantity;
    _pendingAmount ??= amount;
    setState(() => _submitting = true);
    try {
      final result = await context.read<ServiceRepository>().checkout(
        operationId: _pendingOperationId!, serviceId: service.id, quantity: _quantity, method: 'cash', amount: amount,
      );
      if (!mounted) return;
      setState(() { _confirmation = result['sale_number']?.toString() ?? 'Sale completed'; _statusUnknown = false; });
    } catch (error) {
      if (mounted) setState(() => _statusUnknown = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout status unconfirmed. Check sales history before retrying: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Service checkout')),
    body: FutureBuilder<List<ServiceEntry>>(
      future: _services,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load services: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final services = snapshot.data!.where((s) => s.isActive).toList();
        if (services.isEmpty) return const Center(child: Text('Add an active service in the Services catalogue first.'));
        return Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (_confirmation != null) ...[
              Card(child: ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                title: const Text('Payment recorded'),
                subtitle: Text('Sale: $_confirmation'),
              )),
              FilledButton.tonal(
                onPressed: () => setState(() { _confirmation = null; _selected = null; _quantity = 1; _pendingOperationId = null; _pendingServiceId = null; _pendingQuantity = null; _pendingAmount = null; }),
                child: const Text('New checkout'),
              ),
            ] else ...[
              const Text('Select a service'),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _selected?.id,
                onChanged: _submitting || _pendingOperationId != null ? (value) {} : (value) => setState(() => _selected = services.firstWhere((item) => item.id == value)),
                child: Column(children: services.map((service) => RadioListTile<String>(
                title: Text(service.name),
                subtitle: Text('M ${service.price} • ${service.durationMinutes ?? '-'} minutes'),
                value: service.id,
              )).toList()),
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Text('Quantity'),
                const Spacer(),
                IconButton(onPressed: _quantity > 1 && !_submitting && _pendingOperationId == null ? () => setState(() => _quantity--) : null, icon: const Icon(Icons.remove)),
                Text('$_quantity'),
                IconButton(onPressed: _quantity < 10000 && !_submitting && _pendingOperationId == null ? () => setState(() => _quantity++) : null, icon: const Icon(Icons.add)),
              ]),
              const SizedBox(height: 12),
              Text('Total: M ${((double.tryParse(_selected?.price ?? '') ?? 0) * _quantity).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 18),
              if (_statusUnknown) Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Transaction confirmation is unknown. Check sales history first. Retrying uses the SAME operation ID, not a new sale. Reference: $_pendingOperationId'),
              ),
              FilledButton.icon(
                onPressed: _selected == null || _submitting ? null : _checkout,
                icon: const Icon(Icons.payments_outlined),
                label: Text(_submitting ? 'Recording payment…' : _statusUnknown ? 'Verify by retrying same transaction' : 'Record cash payment'),
              ),
              const SizedBox(height: 12),
              const Text('Cash only in this initial version. Do not record a card or mobile-money payment until provider confirmation is implemented.'),
            ],
          ]),
        ));
      },
    ),
  );
}
