import 'package:flutter/material.dart';
import 'package:khanya_pos/features/platform/presentation/platform_admin_page.dart';
import 'package:khanya_pos/features/platform/presentation/platform_subscriptions_page.dart';

class PlatformAdminShellPage extends StatefulWidget {
  const PlatformAdminShellPage({super.key});

  @override
  State<PlatformAdminShellPage> createState() => _PlatformAdminShellPageState();
}

class _PlatformAdminShellPageState extends State<PlatformAdminShellPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = const [
      PlatformAdminPage(),
      PlatformSubscriptionsPage(),
    ];

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  selectedIcon: Icon(Icons.fact_check),
                  label: Text('Approvals'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.workspace_premium_outlined),
                  selectedIcon: Icon(Icons.workspace_premium),
                  label: Text('Billing'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: IndexedStack(index: _index, children: pages)),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Approvals',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Billing',
          ),
        ],
      ),
    );
  }
}
