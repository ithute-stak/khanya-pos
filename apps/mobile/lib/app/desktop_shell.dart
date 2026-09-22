import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/connectivity/connectivity_bloc.dart';
import 'package:khanya_pos/core/realtime/realtime_bloc.dart';
import 'package:khanya_pos/core/sync/sync_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.location,
    required this.child,
  });

  static const double breakpoint = 1100;

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) return child;

        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.f1): () => context.go('/'),
            const SingleActivator(LogicalKeyboardKey.f2): () => context.go('/pos'),
            const SingleActivator(LogicalKeyboardKey.f3): () => context.go('/products'),
            const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => context.go('/customers'),
            const SingleActivator(LogicalKeyboardKey.f5): () => context.go('/inventory'),
            const SingleActivator(LogicalKeyboardKey.f6): () => context.go('/purchases'),
            const SingleActivator(LogicalKeyboardKey.f7): () => context.go('/suppliers'),
            const SingleActivator(LogicalKeyboardKey.f8): () => context.go('/receipts'),
            const SingleActivator(LogicalKeyboardKey.f10): () => context.go('/expenses'),
          },
          child: Focus(
            autofocus: true,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  _DesktopSidebar(location: location),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final role = _selectedRole(context.watch<SessionBloc>().state);
    final visibleItems = _items.where((item) => item.isVisibleFor(role)).toList(growable: false);

    return SizedBox(
      width: 252,
      child: Material(
        color: scheme.surface,
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Image.asset(
                    'assets/branding/khanya_resources_horizontal.webp',
                    height: 58,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'KHANYA POS',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final item in visibleItems)
                        _DesktopNavTile(item: item, selected: item.matches(location)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const _DesktopSystemStatus(),
                const SizedBox(height: 12),
                Text(
                  'F1 Dashboard  •  F2 New Sale\nF3 Products  •  Ctrl+4 Customers\nF5 Inventory  •  F6 Purchases',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNavTile extends StatelessWidget {
  const _DesktopNavTile({required this.item, required this.selected});

  final _DesktopNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(item.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, size: 21, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
                if (item.shortcut != null)
                  Text(
                    item.shortcut!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground.withValues(alpha: 0.72),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSystemStatus extends StatelessWidget {
  const _DesktopSystemStatus();

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityBloc>().state;
    final sync = context.watch<SyncBloc>().state;
    final realtime = context.watch<RealtimeBloc>().state;
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connectivity.isNetworkAvailable ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  size: 18,
                  color: connectivity.isNetworkAvailable ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  connectivity.isNetworkAvailable ? 'Online' : 'Offline mode',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sync.isSyncing
                  ? 'Synchronising…'
                  : sync.pendingCount == 0
                      ? 'All changes synced'
                      : '${sync.pendingCount} change(s) queued',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              realtime.connected ? 'Realtime connected' : 'Realtime reconnecting',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopNavItem {
  const _DesktopNavItem({
    required this.label,
    required this.path,
    required this.icon,
    this.shortcut,
    this.allowedRoles,
  });

  final String label;
  final String path;
  final IconData icon;
  final String? shortcut;
  final Set<String>? allowedRoles;

  bool matches(String location) {
    if (path == '/') return location == '/';
    return location == path || location.startsWith('$path/');
  }

  bool isVisibleFor(String? role) => allowedRoles == null || (role != null && allowedRoles!.contains(role));
}

String? _selectedRole(SessionState state) {
  if (state is! SessionAuthenticated) return null;
  final tenantId = state.session.selectedTenantId;
  for (final membership in state.session.memberships) {
    if (membership.tenantId == tenantId) return membership.role;
  }
  return null;
}

const _items = <_DesktopNavItem>[
  _DesktopNavItem(label: 'Dashboard', path: '/', icon: Icons.dashboard_outlined, shortcut: 'F1'),
  _DesktopNavItem(label: 'New Sale', path: '/pos', icon: Icons.point_of_sale_outlined, shortcut: 'F2'),
  _DesktopNavItem(label: 'Sales History', path: '/sales', icon: Icons.history_outlined),
  _DesktopNavItem(label: 'Till & Shift', path: '/till', icon: Icons.price_check_outlined),
  _DesktopNavItem(
    label: 'Reports',
    path: '/reports',
    icon: Icons.analytics_outlined,
    allowedRoles: {'owner', 'admin', 'manager', 'accountant'},
  ),
  _DesktopNavItem(
    label: 'Accounting',
    path: '/accounting',
    icon: Icons.account_balance_outlined,
    allowedRoles: {'owner', 'admin', 'manager', 'accountant'},
  ),
  _DesktopNavItem(
    label: 'Staff & Roles',
    path: '/staff',
    icon: Icons.manage_accounts_outlined,
    allowedRoles: {'owner', 'admin', 'manager'},
  ),
  _DesktopNavItem(label: 'Products', path: '/products', icon: Icons.inventory_2_outlined, shortcut: 'F3'),
  _DesktopNavItem(label: 'Customers', path: '/customers', icon: Icons.groups_2_outlined, shortcut: 'Ctrl+4'),
  _DesktopNavItem(label: 'Inventory', path: '/inventory', icon: Icons.warehouse_outlined, shortcut: 'F5'),
  _DesktopNavItem(
    label: 'Purchases',
    path: '/purchases',
    icon: Icons.shopping_bag_outlined,
    shortcut: 'F6',
  ),
  _DesktopNavItem(label: 'Suppliers', path: '/suppliers', icon: Icons.local_shipping_outlined, shortcut: 'F7'),
  _DesktopNavItem(label: 'Receipt Vault', path: '/receipts', icon: Icons.receipt_long_outlined, shortcut: 'F8'),
  _DesktopNavItem(label: 'Expenses', path: '/expenses', icon: Icons.account_balance_wallet_outlined, shortcut: 'F10'),
  _DesktopNavItem(
    label: 'POS Hardware',
    path: '/settings/hardware',
    icon: Icons.settings_input_component_outlined,
  ),
];
