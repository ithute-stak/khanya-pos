import 'package:flutter/material.dart';
import 'package:khanya_pos/core/branding/ithute_brand.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.onSignIn,
    required this.onCreateAccount,
  });

  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final PageController _controller = PageController();
  int _step = 0;

  static const int _stepCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == _stepCount - 1) {
      widget.onCreateAccount();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_step == 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: KhanyaBrandedBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 680;
              final horizontal = compact ? 18.0 : 32.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const KhanyaBrandTitle(compact: true),
                            const SizedBox(width: 10),
                            if (!compact)
                              const Expanded(
                                child: IthuteProductBadge(compact: true),
                              )
                            else
                              const Spacer(),
                            TextButton.icon(
                              onPressed: widget.onSignIn,
                              icon: const Icon(Icons.login_rounded, size: 18),
                              label: const Text('Sign in'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: PageView(
                            controller: _controller,
                            onPageChanged: (index) => setState(() => _step = index),
                            children: const [
                              _WelcomeStep(),
                              _WorkspaceStep(),
                              _GetStartedStep(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ProgressDots(
                          current: _step,
                          count: _stepCount,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (_step > 0)
                              TextButton.icon(
                                onPressed: _back,
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text('Back'),
                              )
                            else
                              const SizedBox(width: 88),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _next,
                              icon: Icon(
                                _step == _stepCount - 1
                                    ? Icons.storefront_outlined
                                    : Icons.arrow_forward_rounded,
                              ),
                              label: Text(
                                _step == _stepCount - 1
                                    ? 'Open account'
                                    : 'Continue',
                              ),
                            ),
                          ],
                        ),
                        if (compact) ...[
                          const SizedBox(height: 10),
                          Text(
                            IthuteBrand.productByline,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StepScroll(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 122,
            height: 122,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16062F68),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const KhanyaMark(size: 108, radius: 24),
          ),
          const SizedBox(height: 14),
          const IthuteProductBadge(compact: true),
          const SizedBox(height: 16),
          Text(
            'Welcome to Khanya',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: KhanyaBrand.navy,
              fontWeight: FontWeight.w900,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'A simpler way to run sales, stock, customers and day-to-day business operations.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          const _HighlightPill(
            icon: Icons.offline_bolt_outlined,
            text: 'Built to keep working even when connectivity is unreliable',
          ),
          const SizedBox(height: 10),
          const _HighlightPill(
            icon: Icons.devices_outlined,
            text: 'Use Khanya on mobile and desktop',
          ),
        ],
      ),
    );
  }
}

class _WorkspaceStep extends StatelessWidget {
  const _WorkspaceStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StepScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'One workspace for your business',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: KhanyaBrand.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start with what you need now. Khanya keeps the rest organised as your business grows.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          const _FeatureGrid(),
        ],
      ),
    );
  }
}

class _GetStartedStep extends StatelessWidget {
  const _GetStartedStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StepScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Get your workspace ready',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: KhanyaBrand.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Opening a Khanya account is a short guided process.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          const _OnboardingStep(
            number: '1',
            title: 'Create your account',
            description: 'Enter the owner or administrator details.',
          ),
          const SizedBox(height: 10),
          const _OnboardingStep(
            number: '2',
            title: 'Add your business',
            description: 'Set the business name and operating details.',
          ),
          const SizedBox(height: 10),
          const _OnboardingStep(
            number: '3',
            title: 'Review & activate',
            description: 'Your application is reviewed before the workspace is activated.',
          ),
          const SizedBox(height: 18),
          const Center(child: IthuteProductBadge()),
        ],
      ),
    );
  }
}

class _StepScroll extends StatelessWidget {
  const _StepScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final twoColumns = width >= 620;

    const cards = [
      _CompactFeature(
        icon: Icons.point_of_sale_outlined,
        title: 'Sales',
        description: 'POS, receipts, tills and sales history.',
      ),
      _CompactFeature(
        icon: Icons.inventory_2_outlined,
        title: 'Inventory',
        description: 'Products, stock movements and purchasing.',
      ),
      _CompactFeature(
        icon: Icons.people_outline,
        title: 'Customers',
        description: 'Customer accounts, balances and payments.',
      ),
      _CompactFeature(
        icon: Icons.insights_outlined,
        title: 'Business insights',
        description: 'Expenses, reports and management KPIs.',
      ),
    ];

    if (!twoColumns) {
      return Column(
        children: [
          for (final card in cards) ...[
            card,
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final card in cards)
          SizedBox(
            width: 330,
            child: card,
          ),
      ],
    );
  }
}

class _CompactFeature extends StatelessWidget {
  const _CompactFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE8F3EA),
              foregroundColor: KhanyaBrand.forestDark,
              child: Icon(icon),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: KhanyaBrand.forestDark,
              foregroundColor: Colors.white,
              child: Text(
                number,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightPill extends StatelessWidget {
  const _HighlightPill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: KhanyaBrand.forestDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.current,
    required this.count,
  });

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          count,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: index == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: index == current
                  ? KhanyaBrand.forestDark
                  : Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}
