import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';

abstract final class IthuteBrand {
  static const String companyName = 'Ithute Digital Solutions';
  static const String productByline = 'A product of Ithute Digital Solutions';
  static const String markAsset = 'assets/branding/ithute_ids_mark.svg';

  static const Color navy = Color(0xFF07376F);
  static const Color blue = Color(0xFF1475D1);
  static const Color green = Color(0xFF58AE21);
  static const Color deepGreen = Color(0xFF249716);
  static const Color canvas = Color(0xFFF7FAFD);
}

class IthuteMark extends StatelessWidget {
  const IthuteMark({super.key, this.size = 108});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ithute Digital Solutions logo',
      image: true,
      child: SvgPicture.asset(
        IthuteBrand.markAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

class IthuteBootstrapGate extends StatefulWidget {
  const IthuteBootstrapGate({
    super.key,
    required this.child,
    this.minimumDuration = const Duration(milliseconds: 1500),
  });

  final Widget child;
  final Duration minimumDuration;

  @override
  State<IthuteBootstrapGate> createState() => _IthuteBootstrapGateState();
}

class _IthuteBootstrapGateState extends State<IthuteBootstrapGate> {
  Timer? _timer;
  bool _showBootstrap = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.minimumDuration, () {
      if (!mounted) return;
      setState(() => _showBootstrap = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showBootstrap
          ? const IthuteBootstrapView(key: ValueKey('ithute-bootstrap'))
          : KeyedSubtree(
              key: const ValueKey('khanya-app'),
              child: widget.child,
            ),
    );
  }
}

class IthuteBootstrapView extends StatelessWidget {
  const IthuteBootstrapView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: IthuteBrand.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -150,
            right: -110,
            child: _BootstrapOrb(
              size: 330,
              color: Color(0x161475D1),
            ),
          ),
          const Positioned(
            bottom: -150,
            left: -120,
            child: _BootstrapOrb(
              size: 360,
              color: Color(0x1858AE21),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 540;
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 28 : 44,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: compact ? 132 : 156,
                            height: compact ? 132 : 156,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(34),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x16062F68),
                                  blurRadius: 30,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: IthuteMark(size: compact ? 100 : 122),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Ithute',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: IthuteBrand.navy,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'DIGITAL SOLUTIONS',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: IthuteBrand.green,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.2,
                            ),
                          ),
                          SizedBox(height: compact ? 30 : 38),
                          Text(
                            'PRESENTS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: IthuteBrand.navy.withValues(alpha: .55),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            KhanyaBrand.appName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: KhanyaBrand.forestDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Business operations, simplified.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: IthuteBrand.navy.withValues(alpha: .68),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 30),
                          const SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.7,
                              color: IthuteBrand.green,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Preparing your Khanya workspace…',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: IthuteBrand.navy.withValues(alpha: .58),
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
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: SafeArea(
              top: false,
              child: Text(
                IthuteBrand.productByline,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: IthuteBrand.navy.withValues(alpha: .5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IthuteProductBadge extends StatelessWidget {
  const IthuteProductBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IthuteMark(size: compact ? 24 : 30),
        SizedBox(width: compact ? 7 : 9),
        Flexible(
          child: Text(
            IthuteBrand.productByline,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: IthuteBrand.navy.withValues(alpha: .7),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _BootstrapOrb extends StatelessWidget {
  const _BootstrapOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
