import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/services/data/service_repository.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  late Future<List<ServiceEntry>> _items;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _items = context.read<ServiceRepository>().list();
  }

  Future<void> _edit([ServiceEntry? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final code = TextEditingController(text: item?.code ?? '');
    final price = TextEditingController(text: item?.price ?? '');
    final category = TextEditingController(text: item?.category ?? '');
    final description = TextEditingController(text: item?.description ?? '');
    final duration = TextEditingController(text: item?.durationMinutes?.toString() ?? '');
    final form = GlobalKey<FormState>();
    var active = item?.isActive ?? true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(item == null ? 'New service' : 'Edit service'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Service name'), validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter a service name' : null),
                    TextFormField(controller: code, decoration: const InputDecoration(labelText: 'Service code'), validator: (v) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v?.trim() ?? '') ? null : 'Use letters, numbers, _ or -'),
                    TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Category (optional)')),
                    TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Description (optional)'), maxLines: 2),
                    TextFormField(controller: price, decoration: const InputDecoration(labelText: 'Price (LSL)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return n == null || n < 0 ? 'Enter a valid price' : null; }),
                    TextFormField(controller: duration, decoration: const InputDecoration(labelText: 'Duration in minutes (optional)'), keyboardType: TextInputType.number, validator: (v) { if ((v ?? '').trim().isEmpty) return null; final n = int.tryParse(v!.trim()); return n == null || n < 1 || n > 10080 ? 'Enter 1–10080 minutes' : null; }),
                    SwitchListTile(value: active, onChanged: (v) => update(() => active = v), title: const Text('Active')),
                  ]),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(onPressed: () async {
                if (!form.currentState!.validate()) return;
                try {
                  await context.read<ServiceRepository>().save(
                    id: item?.id, name: name.text, code: code.text,
                    price: price.text, category: category.text, description: description.text,
                    durationMinutes: duration.text.trim().isEmpty ? null : int.parse(duration.text.trim()), isActive: active,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  setState(_refresh);
                } catch (error) {
                  if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Could not save service: $error')));
                }
              }, child: const Text('Save')),
            ],
          ),
        ),
      );
    } finally {
      name.dispose(); code.dispose(); price.dispose(); category.dispose(); description.dispose(); duration.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Services catalogue'), actions: [
      IconButton(onPressed: () => setState(_refresh), icon: const Icon(Icons.refresh)),
      IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add), tooltip: 'Add service'),
    ]),
    body: FutureBuilder<List<ServiceEntry>>(
      future: _items,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) return Center(child: Text('Could not load services: ${snapshot.error}'));
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) return const Center(child: Text('No services yet. Use + to add your first service.'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final item = snapshot.data![index];
            return Card(child: ListTile(
              leading: const Icon(Icons.design_services_outlined),
              title: Text(item.name),
              subtitle: Text('${item.code} • ${item.category ?? 'Uncategorised'} • ${item.durationMinutes == null ? 'No duration' : '${item.durationMinutes} min'}${item.isActive ? '' : ' • Inactive'}'),
              trailing: Text('M ${item.price}'),
              onTap: () => _edit(item),
            ));
          },
        );
      },
    ),
  );
}
