import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/staff/data/staff_repository.dart';
import 'package:khanya_pos/features/staff/domain/staff_member.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  final _searchController = TextEditingController();
  List<StaffMember> _staff = const [];
  List<StaffBranch> _branches = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = context.read<StaffRepository>();
      final staffFuture = repository.listStaff();
      final branchesFuture = repository.listBranches();
      final staff = await staffFuture;
      final branches = await branchesFuture;
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _branches = branches;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  String get _actorRole {
    final state = context.read<SessionBloc>().state;
    if (state is! SessionAuthenticated) return '';
    final tenantId = state.session.selectedTenantId;
    for (final membership in state.session.memberships) {
      if (membership.tenantId == tenantId) return membership.role;
    }
    return '';
  }

  String? get _currentUserId {
    final state = context.read<SessionBloc>().state;
    return state is SessionAuthenticated ? state.session.userId : null;
  }

  String? get _selectedBranchId {
    final state = context.read<SessionBloc>().state;
    return state is SessionAuthenticated ? state.session.selectedBranchId : null;
  }

  List<StaffMember> get _filteredStaff {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _staff;
    return _staff.where((member) {
      return member.displayName.toLowerCase().contains(query) ||
          member.email.toLowerCase().contains(query) ||
          member.role.toLowerCase().contains(query) ||
          (member.phone?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  Future<void> _openEditor([StaffMember? member]) async {
    final currentUserId = _currentUserId;
    final editingSelf = member?.userId == currentUserId;
    if (member != null && !editingSelf && !_canAssignRole(_actorRole, member.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your role cannot manage this staff member.')),
      );
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => RepositoryProvider.value(
        value: context.read<StaffRepository>(),
        child: _StaffEditorDialog(
          staff: member,
          branches: _branches,
          actorRole: _actorRole,
          editingSelf: editingSelf,
          defaultBranchId: _selectedBranchId,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStaff;
    final activeCount = _staff.where((item) => item.isActive).length;
    final inactiveCount = _staff.length - activeCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Roles'),
        actions: [
          IconButton(
            tooltip: 'Refresh staff',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _openEditor(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add staff'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 900 ? 28.0 : 16.0;
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 100),
              children: [
                _StaffOverviewCard(
                  total: _staff.length,
                  active: activeCount,
                  inactive: inactiveCount,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search name, email, phone or role',
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 54),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _ErrorCard(message: _error!, onRetry: _load)
                else if (filtered.isEmpty)
                  const _EmptyStaffCard()
                else if (constraints.maxWidth >= 900)
                  _StaffTable(
                    staff: filtered,
                    branches: _branches,
                    actorRole: _actorRole,
                    currentUserId: _currentUserId,
                    onEdit: _openEditor,
                  )
                else
                  ...filtered.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StaffCard(
                        member: member,
                        branchNames: _branchNames(member.branchIds),
                        canEdit: member.userId == _currentUserId || _canAssignRole(_actorRole, member.role),
                        onEdit: () => _openEditor(member),
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

  String _branchNames(List<String> ids) {
    final names = _branches
        .where((branch) => ids.contains(branch.id))
        .map((branch) => branch.name)
        .toList(growable: false);
    return names.isEmpty ? 'No branch access' : names.join(', ');
  }
}

class _StaffOverviewCard extends StatelessWidget {
  const _StaffOverviewCard({
    required this.total,
    required this.active,
    required this.inactive,
  });

  final int total;
  final int active;
  final int inactive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 26,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.manage_accounts_outlined, size: 34),
            _Metric(label: 'Staff', value: '$total'),
            _Metric(label: 'Active', value: '$active'),
            _Metric(label: 'Inactive', value: '$inactive'),
            SizedBox(
              width: 360,
              child: Text(
                'Manage staff access by role and branch. Role rules are enforced again by the server for every protected operation.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _StaffTable extends StatelessWidget {
  const _StaffTable({
    required this.staff,
    required this.branches,
    required this.actorRole,
    required this.currentUserId,
    required this.onEdit,
  });

  final List<StaffMember> staff;
  final List<StaffBranch> branches;
  final String actorRole;
  final String? currentUserId;
  final ValueChanged<StaffMember> onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Staff member')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Branch access')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('')),
          ],
          rows: staff.map((member) {
            final branchNames = branches
                .where((branch) => member.branchIds.contains(branch.id))
                .map((branch) => branch.name)
                .join(', ');
            final canEdit = member.userId == currentUserId || _canAssignRole(actorRole, member.role);
            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 250,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          member.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(Text(_roleLabel(member.role))),
                DataCell(SizedBox(width: 220, child: Text(branchNames.isEmpty ? '—' : branchNames))),
                DataCell(_StatusChip(active: member.isActive)),
                DataCell(
                  IconButton(
                    tooltip: canEdit ? 'Edit staff member' : 'You cannot manage this role',
                    onPressed: canEdit ? () => onEdit(member) : null,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ],
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.member,
    required this.branchNames,
    required this.canEdit,
    required this.onEdit,
  });

  final StaffMember member;
  final String branchNames;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(_initials(member.displayName))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.displayName, style: Theme.of(context).textTheme.titleMedium),
                      Text(member.email, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _StatusChip(active: member.isActive),
              ],
            ),
            const SizedBox(height: 14),
            Text('${_roleLabel(member.role)} • $branchNames'),
            if (member.phone != null && member.phone!.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(member.phone!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: canEdit ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle_outline : Icons.pause_circle_outline,
        size: 16,
        color: active ? scheme.primary : scheme.error,
      ),
      label: Text(active ? 'Active' : 'Inactive'),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _EmptyStaffCard extends StatelessWidget {
  const _EmptyStaffCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: Text('No staff members match this search.')),
      ),
    );
  }
}

class _StaffEditorDialog extends StatefulWidget {
  const _StaffEditorDialog({
    required this.staff,
    required this.branches,
    required this.actorRole,
    required this.editingSelf,
    required this.defaultBranchId,
  });

  final StaffMember? staff;
  final List<StaffBranch> branches;
  final String actorRole;
  final bool editingSelf;
  final String? defaultBranchId;

  @override
  State<_StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends State<_StaffEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  late String _role;
  late Set<String> _branchIds;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.staff == null;

  @override
  void initState() {
    super.initState();
    final assignable = _assignableRoles(widget.actorRole);
    _nameController = TextEditingController(text: widget.staff?.displayName ?? '');
    _emailController = TextEditingController(text: widget.staff?.email ?? '');
    _phoneController = TextEditingController(text: widget.staff?.phone ?? '');
    _passwordController = TextEditingController();
    _role = widget.staff?.role ?? (assignable.contains('cashier') ? 'cashier' : assignable.firstOrNull ?? 'cashier');
    _branchIds = widget.staff?.branchIds.toSet() ?? <String>{};
    if (_creating && _branchIds.isEmpty && widget.defaultBranchId != null) {
      _branchIds.add(widget.defaultBranchId!);
    }
    _isActive = widget.staff?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_branchIds.isEmpty) {
      setState(() => _error = 'Select at least one branch.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = context.read<StaffRepository>();
      if (_creating) {
        await repository.createStaff(
          displayName: _nameController.text.trim(),
          email: _emailController.text.trim().toLowerCase(),
          phone: _nullable(_phoneController.text),
          password: _nullable(_passwordController.text),
          role: _role,
          branchIds: _branchIds.toList(growable: false),
        );
      } else {
        await repository.updateStaff(
          staff: widget.staff!,
          displayName: _nameController.text.trim(),
          phone: _nullable(_phoneController.text),
          role: _role,
          branchIds: _branchIds.toList(growable: false),
          isActive: _isActive,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignable = _assignableRoles(widget.actorRole);
    final roles = widget.editingSelf ? <String>[_role] : assignable;

    return AlertDialog(
      title: Text(_creating ? 'Add staff member' : 'Edit staff member'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => (value?.trim().length ?? 0) < 2 ? 'Enter the staff member name.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  enabled: _creating && !_saving,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (!text.contains('@') || text.length < 3) return 'Enter a valid email address.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ),
                if (_creating) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_saving,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Temporary password',
                      helperText: 'At least 8 characters. The user can sign in with this password.',
                    ),
                    validator: (value) {
                      final text = value ?? '';
                      if (text.length < 8) return 'Use at least 8 characters.';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: roles
                      .map((role) => DropdownMenuItem(value: role, child: Text(_roleLabel(role))))
                      .toList(growable: false),
                  onChanged: widget.editingSelf || _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _role = value);
                        },
                ),
                const SizedBox(height: 18),
                Text('Branch access', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.branches.map((branch) {
                    return FilterChip(
                      label: Text(branch.isMain ? '${branch.name} • Main' : branch.name),
                      selected: _branchIds.contains(branch.id),
                      onSelected: widget.editingSelf || _saving
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _branchIds.add(branch.id);
                                } else {
                                  _branchIds.remove(branch.id);
                                }
                              });
                            },
                    );
                  }).toList(growable: false),
                ),
                if (!_creating) ...[
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active staff membership'),
                    subtitle: Text(
                      widget.editingSelf
                          ? 'You cannot deactivate your own membership.'
                          : 'Inactive staff cannot access this business.',
                    ),
                    value: _isActive,
                    onChanged: widget.editingSelf || _saving ? null : (value) => setState(() => _isActive = value),
                  ),
                ],
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
              : Icon(_creating ? Icons.person_add_alt_1 : Icons.save_outlined),
          label: Text(_creating ? 'Create staff' : 'Save changes'),
        ),
      ],
    );
  }
}

List<String> _assignableRoles(String actorRole) {
  switch (actorRole) {
    case 'owner':
      return const ['owner', 'admin', 'manager', 'cashier', 'accountant', 'stock_clerk'];
    case 'admin':
      return const ['admin', 'manager', 'cashier', 'accountant', 'stock_clerk'];
    case 'manager':
      return const ['cashier', 'stock_clerk'];
    default:
      return const [];
  }
}

bool _canAssignRole(String actorRole, String targetRole) => _assignableRoles(actorRole).contains(targetRole);

String _roleLabel(String role) {
  switch (role) {
    case 'owner':
      return 'Owner';
    case 'admin':
      return 'Administrator';
    case 'manager':
      return 'Manager';
    case 'cashier':
      return 'Cashier';
    case 'accountant':
      return 'Accountant';
    case 'stock_clerk':
      return 'Stock Clerk';
    default:
      return role;
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

String? _nullable(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _messageFor(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail != null) return detail.toString();
    }
    if (data is Map) {
      final detail = data['detail'];
      if (detail != null) return detail.toString();
    }
  }
  return 'Unable to complete the staff request. Check the connection and try again.';
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
