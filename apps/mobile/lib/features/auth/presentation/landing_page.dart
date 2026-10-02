import 'package:flutter/material.dart';
import 'package:khanya_pos/core/branding/ithute_brand.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({
    super.key,
    required this.onSignIn,
    required this.onCreateAccount,
  });

  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: KhanyaBrandedBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 920;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 56 : 20,
                  vertical: 28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const KhanyaLogo(height: 66, borderRadius: 14),
                            const Spacer(),
                            TextButton(onPressed: onSignIn, child: const Text('Sign in')),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: onCreateAccount,
                              child: const Text('Open an account'),
                            ),
                          ],
                        ),
                        SizedBox(height: wide ? 70 : 42),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: _HeroCopy(onCreateAccount: onCreateAccount)),
                              const SizedBox(width: 54),
                              const Expanded(child: _HeroCard()),
                            ],
                          )
                        else ...[
                          _HeroCopy(onCreateAccount: onCreateAccount),
                          const SizedBox(height: 32),
                          const _HeroCard(),
                        ],
                        const SizedBox(height: 56),
                        Text(
                          'Everything a growing business needs in one place',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: KhanyaBrand.navy,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: const [
                            _FeatureCard(
                              icon: Icons.point_of_sale_outlined,
                              title: 'Sell with confidence',
                              description: 'Fast POS, receipts, tills, shifts, sales history and refunds.',
                            ),
                            _FeatureCard(
                              icon: Icons.inventory_2_outlined,
                              title: 'Know your stock',
                              description: 'Products, purchases, suppliers, stock movements and inventory controls.',
                            ),
                            _FeatureCard(
                              icon: Icons.account_balance_outlined,
                              title: 'Understand the numbers',
                              description: 'Expenses, accounting, cash flow, statements and management reports.',
                            ),
                            _FeatureCard(
                              icon: Icons.cloud_off_outlined,
                              title: 'Keep working offline',
                              description: 'Continue key work during unstable connectivity and sync safely later.',
                            ),
                          ],
                        ),
                        const SizedBox(height: 34),
                        const Center(child: IthuteProductBadge()),
                        const SizedBox(height: 24),
                        Card(
                          color: scheme.primaryContainer.withValues(alpha: 0.55),
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: wide
                                ? Row(
                                    children: [
                                      const Expanded(child: _ApprovalCopy()),
                                      const SizedBox(width: 24),
                                      FilledButton.icon(
                                        onPressed: onCreateAccount,
                                        icon: const Icon(Icons.storefront_outlined),
                                        label: const Text('Register your business'),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const _ApprovalCopy(),
                                      const SizedBox(height: 18),
                                      FilledButton.icon(
                                        onPressed: onCreateAccount,
                                        icon: const Icon(Icons.storefront_outlined),
                                        label: const Text('Register your business'),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onCreateAccount});

  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFE8F3EA),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              'KHANYA BUSINESS OPERATING SYSTEM',
              style: TextStyle(
                color: KhanyaBrand.forestDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Run your business with clarity — from the first sale to the final report.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: KhanyaBrand.navy,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
        ),
        const SizedBox(height: 18),
        Text(
          'Khanya brings sales, customers, inventory, purchasing, expenses, staff and accounting into one secure workspace built for real day-to-day operations.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.black.withValues(alpha: 0.68),
                height: 1.55,
              ),
        ),
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: onCreateAccount,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Open your Khanya account'),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'New business accounts are reviewed before activation.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, color: scheme.primary, size: 30),
                const SizedBox(width: 12),
                Text(
                  'One live business picture',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _HeroMetric(label: 'Sales today', value: 'Live'),
            const _HeroMetric(label: 'Stock health', value: 'Tracked'),
            const _HeroMetric(label: 'Expenses', value: 'Controlled'),
            const _HeroMetric(label: 'Accounting', value: 'Connected'),
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8F5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: KhanyaBrand.forest),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Each business is isolated as its own tenant, with role and branch access controls.',
                      ),
                    ),
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

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: KhanyaBrand.forestDark,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.icon, required this.title, required this.description});
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: width >= 920 ? 270 : width - 40,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: KhanyaBrand.forest, size: 30),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(description, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalCopy extends StatelessWidget {
  const _ApprovalCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ready to join Khanya?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          'Register your business and owner details. The Khanya platform team reviews the application before the workspace is activated.',
        ),
      ],
    );
  }
}
