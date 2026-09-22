import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:khanya_pos/features/devices/data/device_repository.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<ManagedDevice> _devices = const [];
  List<DeviceBranch> _branches = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = context.read<DeviceRepository>();
      final results = await Future.wait([repository.listDevices(), repository.listBranches()]);
      if (!mounted) return;
      setState(() {
        _devices = results[0] as List<ManagedDevice>;
        _branches = results[1] as List<DeviceBranch>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _edit(ManagedDevice device) async {
    final nameController = TextEditingController(text: device.name);
    var branchId = device.branchId;
    var active = device.isActive;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit workstation'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Workstation name'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: branchId,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: _branches
                      .map((branch) => DropdownMenuItem(value: branch.id, child: Text(branch.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => branchId = value);
                  },
                ),
                SwitchListTile(
                  value: active,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active workstation'),
                  subtitle: const Text('Inactive workstations remain in history but can be blocked from use.'),
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;

    try {
      await context.read<DeviceRepository>().updateDevice(
            device: device,
            name: nameController.text.trim(),
            branchId: branchId,
            isActive: active,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Workstation updated')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $error')));
    } finally {
      nameController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workstations & Devices'),
        actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load workstations.\n$_error', textAlign: TextAlign.center))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Registered POS workstations',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'See which PCs and tills are registered, where they belong, the installed app version and when they were last seen.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      if (_devices.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No registered workstations yet.')))
                      else
                        ..._devices.map((device) => _DeviceCard(device: device, onEdit: () => _edit(device))),
                    ],
                  ),
                ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onEdit});
  final ManagedDevice device;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastSeen = device.lastSeenAt == null
        ? 'Never seen'
        : DateFormat('dd MMM yyyy, HH:mm').format(device.lastSeenAt!);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: device.recentlySeen && device.isActive
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          child: Icon(device.platform.toLowerCase().contains('windows') ? Icons.desktop_windows : Icons.devices),
        ),
        title: Row(
          children: [
            Expanded(child: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            Chip(label: Text(device.isActive ? (device.recentlySeen ? 'Online' : 'Active') : 'Inactive')),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${device.branchName}  •  ${device.platform}  •  ${device.deviceType}\n'
            'Version ${device.appVersion ?? 'unknown'}  •  Last seen $lastSeen',
          ),
        ),
        trailing: IconButton(onPressed: onEdit, tooltip: 'Manage workstation', icon: const Icon(Icons.edit_outlined)),
      ),
    );
  }
}
