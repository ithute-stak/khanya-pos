import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class BusinessContextPage extends StatelessWidget {
  const BusinessContextPage({super.key, required this.state});
  final SessionAuthenticated state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose business')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Where are you working?', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('Select a business and one of the branches assigned to your account.'),
          const SizedBox(height: 20),
          for (final membership in state.session.memberships)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(membership.tenantName, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(membership.role.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 12),
                    if (membership.branchIds.isEmpty)
                      const Text('No branch has been assigned to this account yet.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var index = 0; index < membership.branchIds.length; index++)
                            ActionChip(
                              avatar: const Icon(Icons.store_mall_directory_outlined, size: 18),
                              label: Text(membership.branchIds.length == 1 ? 'Open branch' : 'Branch ${index + 1}'),
                              onPressed: () => context.read<SessionBloc>().add(
                                    SessionBusinessSelected(
                                      tenantId: membership.tenantId,
                                      branchId: membership.branchIds[index],
                                    ),
                                  ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => context.read<SessionBloc>().add(const SessionSignedOut()),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
