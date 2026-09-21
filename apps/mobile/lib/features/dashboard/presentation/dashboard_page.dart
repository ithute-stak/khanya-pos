import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/connectivity/connectivity_bloc.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khanya POS'),
        actions: [
          BlocBuilder<ConnectivityBloc, ConnectivityState>(
            builder: (context, state) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  avatar: Icon(
                    state.isNetworkAvailable ? Icons.cloud_done : Icons.cloud_off,
                    size: 18,
                  ),
                  label: Text(state.isNetworkAvailable ? 'Online' : 'Offline'),
                ),
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 700 ? 32.0 : 16.0;
          return ListView(
            padding: EdgeInsets.all(horizontalPadding),
            children: [
              Text(
                'Foundation ready',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Khanya POS is ready for tenant-aware feature modules, offline sync, BLoC events and realtime updates.',
              ),
              const SizedBox(height: 24),
              const Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FoundationCard(title: 'POS', icon: Icons.point_of_sale),
                  _FoundationCard(title: 'Inventory', icon: Icons.inventory_2_outlined),
                  _FoundationCard(title: 'Purchases', icon: Icons.shopping_cart_outlined),
                  _FoundationCard(title: 'Receipts', icon: Icons.receipt_long_outlined),
                  _FoundationCard(title: 'Expenses', icon: Icons.account_balance_wallet_outlined),
                  _FoundationCard(title: 'Accounting', icon: Icons.account_balance_outlined),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FoundationCard extends StatelessWidget {
  const _FoundationCard({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
