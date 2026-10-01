import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/workforce/data/workforce_repository.dart';

class WorkforcePage extends StatefulWidget {
  const WorkforcePage({super.key});

  @override
  State<WorkforcePage> createState() => _WorkforcePageState();
}

class _WorkforcePageState extends State<WorkforcePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _me = const {};
  List<Map<String, dynamic>> _shifts = const [];
  List<Map<String, dynamic>> _attendance = const [];
  List<Map<String, dynamic>> _staff = const [];

  WorkforceRepository get _repository => context.read<WorkforceRepository>();

  bool get _canManage {
    final state = context.read<SessionBloc>().state;
    if (state is! SessionAuthenticated) return false;
    final tenantId = state.session.selectedTenantId;
    for (final membership in state.session.memberships) {
      if (membership.tenantId == tenantId) {
        return {'owner', 'admin', 'manager'}.contains(membership.role);
      }
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
      final me = await _repository.myAttendance();
      List<Map<String, dynamic>> shifts = const [];
      List<Map<String, dynamic>> attendance = const [];
      List<Map<String, dynamic>> staff = const [];
      if (_canManage) {
        final management = await Future.wait([
          _repository.shifts(),
          _repository.attendance(),
          _repository.staff(),
        ]);
        shifts = management[0];
        attendance = management[1];
        staff = management[2];
      }
      if (!mounted) return;
      setState(() {
        _me = me;
        _shifts = shifts;
        _attendance = attendance;
        _staff = staff;
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

  Future<void> _punch() async {
    final clockedIn = _me['clocked_in'] == true;
    await _repository.punch(clockedIn ? 'out' : 'in');
    await _load();
  }

  Future<void> _createShift() async {
    String? membershipId;
    final note = TextEditingController();
    DateTime startsAt = DateTime.now().add(const Duration(hours: 1));
    DateTime endsAt = startsAt.add(const Duration(hours: 8));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule staff shift'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: membershipId,
                  decoration: const InputDecoration(labelText: 'Staff member'),
                  items: _staff
                      .map((item) => DropdownMenuItem<String>(
                            value: item['membership_id']?.toString(),
                            child: Text(item['display_name']?.toString() ?? 'Staff'),
                          ))
                      .toList(),
                  onChanged: (value) => setDialogState(() => membershipId = value),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Starts'),
                  subtitle: Text(startsAt.toLocal().toString()),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: startsAt,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(startsAt));
                    if (time == null) return;
                    setDialogState(() {
                      startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      if (!endsAt.isAfter(startsAt)) endsAt = startsAt.add(const Duration(hours: 8));
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ends'),
                  subtitle: Text(endsAt.toLocal().toString()),
                  trailing: const Icon(Icons.schedule_outlined),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: endsAt,
                      firstDate: startsAt,
                      lastDate: startsAt.add(const Duration(days: 30)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(endsAt));
                    if (time == null) return;
                    setDialogState(() => endsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                  },
                ),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: membershipId == null ? null : () => Navigator.pop(context, true), child: const Text('Schedule')),
          ],
        ),
      ),
    );
    if (saved != true || membershipId == null) return;
    await _repository.createShift(
      membershipId: membershipId!,
      startsAt: startsAt,
      endsAt: endsAt,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workforce')),
        body: Center(child: FilledButton(onPressed: _load, child: Text('Retry: $_error'))),
      );
    }
    final clockedIn = _me['clocked_in'] == true;
    final punches = (_me['punches'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workforce'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clockedIn ? 'You are clocked in' : 'You are clocked out', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      const Text('Attendance punches are timestamped and retained as an audit trail.'),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _punch,
                    icon: Icon(clockedIn ? Icons.logout : Icons.login),
                    label: Text(clockedIn ? 'Clock out' : 'Clock in'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('My recent attendance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (punches.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No attendance punches yet.')))
          else
            Card(
              child: Column(
                children: [
                  for (final punch in punches.take(10))
                    ListTile(
                      leading: Icon(punch['punch_type'] == 'in' ? Icons.login : Icons.logout),
                      title: Text(punch['punch_type'] == 'in' ? 'Clock in' : 'Clock out'),
                      subtitle: Text(punch['punched_at']?.toString() ?? ''),
                    ),
                ],
              ),
            ),
          if (_canManage) ...[
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Scheduled shifts', style: Theme.of(context).textTheme.titleLarge),
                FilledButton.icon(onPressed: _createShift, icon: const Icon(Icons.add), label: const Text('Schedule shift')),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: _shifts.isEmpty
                  ? const Padding(padding: EdgeInsets.all(20), child: Text('No scheduled shifts in this period.'))
                  : Column(
                      children: [
                        for (final shift in _shifts)
                          ListTile(
                            leading: const Icon(Icons.calendar_month_outlined),
                            title: Text(shift['staff_name']?.toString() ?? 'Staff'),
                            subtitle: Text('${shift['starts_at']} → ${shift['ends_at']}'),
                            trailing: Text(shift['status']?.toString() ?? ''),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 28),
            Text('Today’s attendance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: _attendance.isEmpty
                  ? const Padding(padding: EdgeInsets.all(20), child: Text('No attendance recorded today.'))
                  : Column(
                      children: [
                        for (final row in _attendance)
                          ListTile(
                            leading: Icon(row['punch_type'] == 'in' ? Icons.login : Icons.logout),
                            title: Text(row['staff_name']?.toString() ?? 'Staff'),
                            subtitle: Text(row['punched_at']?.toString() ?? ''),
                            trailing: Text(row['punch_type']?.toString().toUpperCase() ?? ''),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
