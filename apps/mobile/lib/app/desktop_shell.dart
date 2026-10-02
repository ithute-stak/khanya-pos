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
        if (constraints.maxWidth < breakpoint) {
          return _MobileShell(location: location, child: child);
        }

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

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (_hideMobileNavigation(location)) return child;

    final selectedIndex = _mobileDestinationIndex(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          const destinations = <String>[
            '/',
            '/pos',
            '/products',
            '/customers',
            '/more',
          ];
          final target = destinations[index];
          if (target != location) context.go(target);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale_rounded),
            label: 'Sell',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_2_outlined),
            selectedIcon: Icon(Icons.groups_2_rounded),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

int _mobileDestinationIndex(String location) {
  if (location == '/') return 0;
  if (location == '/pos') return 1;
  if (location == '/products' || location.startsWith('/products/')) return 2;
  if (location == '/customers' || location.startsWith('/customers/')) return 3;
  return 4;
}

bool _hideMobileNavigation(String location) {
  if (location.startsWith('/sales/')) return true;
  if (location.startsWith('/customers/') && location != '/customers') return true;
  return location == '/purchases/new' ||
      location == '/expenses/new' ||
      location == '/inventory/controls';
}

class MobileMorePage extends StatelessWidget {
  const MobileMorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final role = _selectedRole(context.watch<SessionBloc>().state);
    final hiddenPaths = <String>{
      '/',
      '/pos',
      '/products',
      '/customers',
    };
    final visibleItems = _items
        .where((item) => !hiddenPaths.contains(item.path) && item.isVisibleFor(role))
        .toList(growable: false);

    final operations = visibleItems.where((item) => _operationsPaths.contains(item.path)).toList();
    final finance = visibleItems.where((item) => _financePaths.contains(item.path)).toList();
    final management = visibleItems
        .where(
          (item) =>
              !_operationsPaths.contains(item.path) &&
              !_financePaths.contains(item.path),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            context.read<SyncBloc>().add(const SyncRequested());
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _MobileMoreHeader(role: role),
              const SizedBox(height: 18),
              if (operations.isNotEmpty) ...[
                _MobileSectionTitle(
                  title: 'Operations',
                  subtitle: 'Run daily business activity',
                ),
                const SizedBox(height: 10),
                _MobileNavigationGrid(items: operations),
                const SizedBox(height: 22),
              ],
              if (finance.isNotEmpty) ...[
                _MobileSectionTitle(
                  title: 'Finance & insights',
                  subtitle: 'Understand performance and cash',
                ),
                const SizedBox(height: 10),
                _MobileNavigationGrid(items: finance),
                const SizedBox(height: 22),
              ],
              if (management.isNotEmpty) ...[
                _MobileSectionTitle(
                  title: 'Team & settings',
                  subtitle: 'Manage people, devices and configuration',
                ),
                const SizedBox(height: 10),
                _MobileNavigationGrid(items: management),
                const SizedBox(height: 22),
              ],
              const _MobileSystemStatusCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMoreHeader extends StatelessWidget {
  const _MobileMoreHeader({required this.role});

  final String? role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roleLabel = (role ?? 'staff')
        .split('_')
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: const Icon(Icons.apps_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Khanya workspace',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Open every business tool available to your role.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Chip(label: Text(roleLabel)),
        ],
      ),
    );
  }
}

class _MobileSectionTitle extends StatelessWidget {
  const _MobileSectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MobileNavigationGrid extends StatelessWidget {
  const _MobileNavigationGrid({required this.items});

  final List<_DesktopNavItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _MobileNavigationCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _MobileNavigationCard extends StatelessWidget {
  const _MobileNavigationCard({required this.item});

  final _DesktopNavItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(item.path),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 108),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(item.icon, size: 20),
                ),
                const SizedBox(height: 14),
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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

class _MobileSystemStatusCard extends StatelessWidget {
  const _MobileSystemStatusCard();

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityBloc>().state;
    final sync = context.watch<SyncBloc>().state;
    final realtime = context.watch<RealtimeBloc>().state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System status',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            _MobileStatusRow(
              icon: connectivity.isNetworkAvailable
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              label: connectivity.isNetworkAvailable ? 'Online' : 'Offline mode',
              value: sync.isSyncing
                  ? 'Synchronising…'
                  : sync.pendingCount == 0
                      ? 'All changes synced'
                      : '${sync.pendingCount} queued',
              emphasis: connectivity.isNetworkAvailable
                  ? scheme.primary
                  : scheme.error,
            ),
            const SizedBox(height: 10),
            _MobileStatusRow(
              icon: realtime.connected
                  ? Icons.bolt_rounded
                  : Icons.bolt_outlined,
              label: realtime.statusLabel,
              value: realtime.connected ? 'Live updates on' : 'Tap to reconnect',
              emphasis: realtime.connected
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
              onTap: realtime.connected
                  ? null
                  : () => context
                      .read<RealtimeBloc>()
                      .add(const RealtimeReconnectNowRequested()),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileStatusRow extends StatelessWidget {
  const _MobileStatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.emphasis,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color emphasis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(icon, color: emphasis, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        if (onTap != null) const Icon(Icons.refresh_rounded, size: 18),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }
}

const _operationsPaths = <String>{
  '/sales',
  '/till',
  '/inventory',
  '/purchases',
  '/purchase-orders',
  '/suppliers',
  '/receipts',
};

const _financePaths = <String>{
  '/reports',
  '/business-os',
  '/accounting',
  '/accounting/management',
  '/accounting/cash-flow',
  '/accounting/statements',
  '/expenses',
};

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
            Row(
              children: [
                Icon(
                  realtime.connected ? Icons.bolt : Icons.bolt_outlined,
                  size: 15,
                  color: realtime.connected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    realtime.statusLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                if (!realtime.connected)
                  IconButton(
                    tooltip: 'Reconnect realtime',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context
                        .read<RealtimeBloc>()
                        .add(const RealtimeReconnectNowRequested()),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                  ),
              ],
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
    if (path == '/' || path == '/accounting') return location == path;
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
    label: 'Business OS',
    path: '/business-os',
    icon: Icons.auto_graph_outlined,
    allowedRoles: {'owner', 'admin', 'manager'},
  ),
  _DesktopNavItem(
    label: 'Accounting',
    path: '/accounting',
    icon: Icons.account_balance_outlined,
    allowedRoles: {'owner', 'admin', 'manager', 'accountant'},
  ),
  _DesktopNavItem(
    label: 'Management Reports',
    path: '/accounting/management',
    icon: Icons.insights_outlined,
    allowedRoles: {'owner', 'admin', 'manager', 'accountant'},
  ),
  _DesktopNavItem(
    label: 'Cash Flow',
    path: '/accounting/cash-flow',
    icon: Icons.waterfall_chart_outlined,
    allowedRoles: {'owner', 'admin', 'manager', 'accountant'},
  ),
  _DesktopNavItem(
    label: 'Financial Statements',
    path: '/accounting/statements',
    icon: Icons.description_outlined,
    allowedRoles: {'owner', 'admin', 'manager', 'accountant'},
  ),
  _DesktopNavItem(
    label: 'Staff & Roles',
    path: '/staff',
    icon: Icons.manage_accounts_outlined,
    allowedRoles: {'owner', 'admin', 'manager'},
  ),
  _DesktopNavItem(
    label: 'Workforce',
    path: '/workforce',
    icon: Icons.badge_outlined,
  ),
  _DesktopNavItem(
    label: 'Workstations',
    path: '/devices',
    icon: Icons.desktop_windows_outlined,
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
  _DesktopNavItem(
    label: 'Purchase Orders',
    path: '/purchase-orders',
    icon: Icons.fact_check_outlined,
    allowedRoles: {'owner', 'admin', 'manager', 'stock_controller'},
  ),
  _DesktopNavItem(label: 'Suppliers', path: '/suppliers', icon: Icons.local_shipping_outlined, shortcut: 'F7'),
  _DesktopNavItem(label: 'Receipt Vault', path: '/receipts', icon: Icons.receipt_long_outlined, shortcut: 'F8'),
  _DesktopNavItem(label: 'Expenses', path: '/expenses', icon: Icons.account_balance_wallet_outlined, shortcut: 'F10'),
  _DesktopNavItem(
    label: 'Business Settings',
    path: '/settings/business',
    icon: Icons.business_outlined,
    allowedRoles: {'owner', 'admin'},
  ),
  _DesktopNavItem(
    label: 'POS Hardware',
    path: '/settings/hardware',
    icon: Icons.settings_input_component_outlined,
  ),
];
