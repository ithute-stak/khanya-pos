import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/settings/data/business_settings_repository.dart';

class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  BusinessSettings? _business;
  List<ManagedBranch> _branches = const [];
  bool _loading = true;
  String? _error;

  bool get _isOwner {
    final state = context.read<SessionBloc>().state;
    if (state is! SessionAuthenticated) return false;
    final tenantId = state.session.selectedTenantId;
    for (final membership in state.session.memberships) {
      if (membership.tenantId == tenantId) return membership.role == 'owner';
    }
    return false;
  }

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
      final repo = context.read<BusinessSettingsRepository>();
      final results = await Future.wait<dynamic>([repo.getBusiness(), repo.listBranches()]);
      if (!mounted) return;
      setState(() {
        _business = results[0] as BusinessSettings;
        _branches = results[1] as List<ManagedBranch>;
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

  Future<void> _editBusinessName() async {
    final current = _business;
    if (current == null) return;
    final controller = TextEditingController(text: current.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Business name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Business name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.length < 2) return;
    try {
      final updated = await context.read<BusinessSettingsRepository>().updateBusinessName(name);
      if (!mounted) return;
      setState(() => _business = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Business name updated')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update business: $error')));
    }
  }

  Future<void> _editBranch([ManagedBranch? branch]) async {
    final result = await showDialog<_BranchFormResult>(
      context: context,
      builder: (context) => _BranchDialog(branch: branch),
    );
    if (result == null) return;
    try {
      final repo = context.read<BusinessSettingsRepository>();
      if (branch == null) {
        await repo.createBranch(
          name: result.name,
          code: result.code,
          location: result.location,
          isMain: result.isMain,
        );
      } else {
        await repo.updateBranch(
          branch: branch,
          name: result.name,
          code: result.code,
          location: result.location,
          isMain: result.isMain,
          isActive: result.isActive,
        );
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(branch == null ? 'Branch created' : 'Branch updated')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save branch: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _BusinessCard(
                        business: _business!,
                        canRename: _isOwner,
                        onRename: _editBusinessName,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Branches', style: Theme.of(context).textTheme.titleLarge),
                          ),
                          FilledButton.icon(
                            onPressed: () => _editBranch(),
                            icon: const Icon(Icons.add_business_outlined),
                            label: const Text('Add branch'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_branches.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No branches found.')))
                      else
                        ..._branches.map(
                          (branch) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BranchCard(branch: branch, onEdit: () => _editBranch(branch)),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business, required this.canRename, required this.onRename});

  final BusinessSettings business;
  final bool canRename;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(business.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Business ID: ${business.slug}'),
              ],
            ),
            if (canRename)
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Rename business'),
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.branch, required this.onEdit});

  final ManagedBranch branch;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(branch.isMain ? Icons.store : Icons.store_outlined)),
        title: Row(
          children: [
            Expanded(child: Text(branch.name)),
            if (branch.isMain) const Chip(label: Text('Main')),
            if (!branch.isActive) const Padding(padding: EdgeInsets.only(left: 6), child: Chip(label: Text('Inactive'))),
          ],
        ),
        subtitle: Text('${branch.code}${branch.location == null ? '' : ' • ${branch.location}'}'),
        trailing: IconButton(onPressed: onEdit, tooltip: 'Edit branch', icon: const Icon(Icons.edit_outlined)),
      ),
    );
  }
}

class _BranchFormResult {
  const _BranchFormResult({
    required this.name,
    required this.code,
    required this.location,
    required this.isMain,
    required this.isActive,
  });

  final String name;
  final String code;
  final String? location;
  final bool isMain;
  final bool isActive;
}

class _BranchDialog extends StatefulWidget {
  const _BranchDialog({this.branch});

  final ManagedBranch? branch;

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _location;
  late bool _isMain;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.branch?.name ?? '');
    _code = TextEditingController(text: widget.branch?.code ?? '');
    _location = TextEditingController(text: widget.branch?.location ?? '');
    _isMain = widget.branch?.isMain ?? false;
    _isActive = widget.branch?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.branch == null ? 'Add branch' : 'Edit branch'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Branch name')),
              const SizedBox(height: 12),
              TextField(controller: _code, decoration: const InputDecoration(labelText: 'Branch code')),
              const SizedBox(height: 12),
              TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isMain,
                onChanged: (value) => setState(() => _isMain = value),
                title: const Text('Main branch'),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.branch != null)
                SwitchListTile(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Active'),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().length < 2 || _code.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _BranchFormResult(
                name: _name.text.trim(),
                code: _code.text.trim(),
                location: _location.text.trim().isEmpty ? null : _location.text.trim(),
                isMain: _isMain,
                isActive: _isActive,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
