import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class WorkspaceSwitcherPage extends StatelessWidget {
  const WorkspaceSwitcherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionBloc>().state;
    if (state is! SessionAuthenticated) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = state.session;

    return Scaffold(
      appBar: AppBar(title: const Text('Switch workspace')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Business & branch',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: KhanyaBrand.navy,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose where you are working. Sales, stock, till and reports will immediately use the selected branch.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    for (final membership in session.memberships) ...[
                      _BusinessWorkspaceCard(
                        membership: membership,
                        selectedTenantId: session.selectedTenantId,
                        selectedBranchId: session.selectedBranchId,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessWorkspaceCard extends StatelessWidget {
  const _BusinessWorkspaceCard({
    required this.membership,
    required this.selectedTenantId,
    required this.selectedBranchId,
  });

  final BusinessMembership membership;
  final String? selectedTenantId;
  final String? selectedBranchId;

  @override
  Widget build(BuildContext context) {
    final selectedBusiness = membership.tenantId == selectedTenantId;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const KhanyaMark(size: 42, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        membership.tenantName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        membership.role.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                if (selectedBusiness)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Current business'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (membership.branchIds.isEmpty)
              const Text('No branch has been assigned to this account.')
            else
              ...List.generate(membership.branchIds.length, (index) {
                final branchId = membership.branchIds[index];
                final branch = membership.branchById(branchId);
                final selected = selectedBusiness && branchId == selectedBranchId;
                final active = branch?.isActive ?? true;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: selected
                        ? scheme.primaryContainer.withValues(alpha: .65)
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: !active
                          ? null
                          : () {
                              context.read<SessionBloc>().add(
                                    SessionBusinessSelected(
                                      tenantId: membership.tenantId,
                                      branchId: branchId,
                                    ),
                                  );
                              context.go('/');
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              branch?.isMain == true
                                  ? Icons.storefront_rounded
                                  : Icons.store_mall_directory_outlined,
                              color: active ? scheme.primary : scheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    membership.branchLabel(
                                      branchId,
                                      fallbackIndex: index,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (branch?.location?.trim().isNotEmpty == true)
                                    Text(
                                      branch!.location!,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            if (!active)
                              const Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('Inactive'),
                              )
                            else if (selected)
                              Icon(Icons.check_circle_rounded, color: scheme.primary)
                            else
                              const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
