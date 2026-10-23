import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/services/data/service_repository.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});
  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  late Future<List<Map<String, dynamic>>> _appointments;
  @override
  void initState() { super.initState(); _reload(); }
  void _reload() => _appointments = context.read<ServiceRepository>().appointments();

  Future<void> _create() async {
    final repository = context.read<ServiceRepository>();
    final services = await repository.list();
    if (!mounted) return;
    final available = services.where((s) => s.isActive && s.durationMinutes != null).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create an active service with a duration first.')));
      return;
    }
    final customer = TextEditingController();
    final staff = TextEditingController();
    final form = GlobalKey<FormState>();
    var serviceId = available.first.id;
    var start = DateTime.now().add(const Duration(hours: 1));
    try {
      await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Book service appointment'),
          content: SizedBox(width: 420, child: SingleChildScrollView(child: Form(key: form, child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: serviceId, decoration: const InputDecoration(labelText: 'Service'),
                items: available.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (v) { if (v != null) update(() => serviceId = v); },
              ),
              TextFormField(controller: customer, decoration: const InputDecoration(labelText: 'Customer / walk-in name'),
                validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter customer name' : null),
              TextFormField(controller: staff, decoration: const InputDecoration(labelText: 'Staff membership UUID (optional)')),
              const SizedBox(height: 14),
              ListTile(
                title: Text('Start: ${start.toLocal()}'),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final day = await showDatePicker(context: context, initialDate: start, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (day == null || !context.mounted) return;
                  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
                  if (time == null) return;
                  update(() => start = DateTime(day.year, day.month, day.day, time.hour, time.minute));
                },
              ),
            ],
          )))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () async {
              if (!form.currentState!.validate()) return;
              try {
                await repository.createAppointment(serviceId: serviceId, customerName: customer.text,
                  startsAt: start, membershipId: staff.text.trim().isEmpty ? null : staff.text.trim());
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                setState(_reload);
              } catch (error) {
                if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Booking failed: $error')));
              }
            }, child: const Text('Book')),
          ],
        ),
      ));
    } finally { customer.dispose(); staff.dispose(); }
  }

  Future<void> _change(Map<String, dynamic> appointment, String status) async {
    try {
      await context.read<ServiceRepository>().updateAppointmentStatus(appointment['id'].toString(), status);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Appointments'), actions: [
      IconButton(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh)),
      IconButton(onPressed: _create, icon: const Icon(Icons.add), tooltip: 'Book appointment'),
    ]),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _appointments,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to load appointments: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty) return const Center(child: Text('No appointments yet. Select + to book a service.'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final item in snapshot.data!) Card(child: ListTile(
            title: Text(item['customer_name']?.toString() ?? 'Customer'),
            subtitle: Text('${item['starts_at']} • ${item['status']}'),
            trailing: PopupMenuButton<String>(
              tooltip: 'Change status',
              onSelected: (status) => _change(item, status),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'checked_in', child: Text('Check in')),
                PopupMenuItem(value: 'in_progress', child: Text('Start service')),
                PopupMenuItem(value: 'completed', child: Text('Complete')),
                PopupMenuItem(value: 'cancelled', child: Text('Cancel')),
                PopupMenuItem(value: 'no_show', child: Text('No-show')),
              ],
            ),
          )),
        ]);
      },
    ),
  );
}
