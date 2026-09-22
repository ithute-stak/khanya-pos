import 'package:flutter/material.dart';

abstract final class KhanyaBrand {
  static const String appName = 'Khanya POS';
  static const String companyName = 'Khanya Resources';
  static const String companyDescriptor = 'Management & Consultancy Services';
  static const String tagline = 'People | Process | Profit | A Brighter Tomorrow';

  static const String appIconAsset =
      'assets/branding/khanya_app_icon_safe.jpg';
  static const String fullLogoAsset =
      'assets/branding/khanya_full_logo.webp';
  static const String horizontalLogoAsset =
      'assets/branding/khanya_resources_horizontal.webp';

  static const Color forest = Color(0xFF006B3C);
  static const Color forestDark = Color(0xFF004B2A);
  static const Color leaf = Color(0xFF3D9B2F);
  static const Color gold = Color(0xFFD4A017);
  static const Color goldDark = Color(0xFFA76F00);
  static const Color navy = Color(0xFF082F49);
  static const Color cream = Color(0xFFFFFCF2);
  static const Color mist = Color(0xFFF4F7F2);
}

class KhanyaLogo extends StatelessWidget {
  const KhanyaLogo({
    super.key,
    this.height = 150,
    this.fit = BoxFit.contain,
    this.borderRadius = 18,
  });

  final double height;
  final BoxFit fit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Khanya Resources — Management & Consultancy Services',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          KhanyaBrand.fullLogoAsset,
          height: height,
          fit: fit,
          filterQuality: FilterQuality.high,
          semanticLabel:
              'Khanya Resources — Management & Consultancy Services',
          errorBuilder: (context, error, stackTrace) => _KhanyaLogoFallback(
            height: height,
            borderRadius: borderRadius,
          ),
        ),
      ),
    );
  }
}

class _KhanyaLogoFallback extends StatelessWidget {
  const _KhanyaLogoFallback({
    required this.height,
    required this.borderRadius,
  });

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final markSize = (height * 0.56).clamp(58.0, 104.0);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          KhanyaMark(size: markSize, radius: borderRadius),
          const SizedBox(width: 18),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KHANYA RESOURCES',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: KhanyaBrand.forestDark,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  KhanyaBrand.companyDescriptor.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: KhanyaBrand.goldDark,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.55,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  KhanyaBrand.tagline,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: KhanyaBrand.navy.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KhanyaMark extends StatelessWidget {
  const KhanyaMark({super.key, this.size = 44, this.radius = 12});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        KhanyaBrand.appIconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Khanya Resources mark',
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: KhanyaBrand.forestDark,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(
            'K',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.48,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class KhanyaBrandTitle extends StatelessWidget {
  const KhanyaBrandTitle({
    super.key,
    this.compact = false,
    this.onDark = false,
  });

  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final foreground = onDark ? Colors.white : KhanyaBrand.navy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KhanyaMark(size: compact ? 34 : 42, radius: compact ? 9 : 11),
        SizedBox(width: compact ? 9 : 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                KhanyaBrand.appName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
              ),
              if (!compact)
                Text(
                  KhanyaBrand.companyName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: onDark ? Colors.white70 : KhanyaBrand.forest,
                        fontWeight: FontWeight.w700,
                      ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class KhanyaBrandedBackground extends StatelessWidget {
  const KhanyaBrandedBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFFFF),
            KhanyaBrand.mist,
            Color(0xFFFFF9E8),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            right: -110,
            top: -90,
            child: _BrandOrb(size: 300, color: Color(0x183D9B2F)),
          ),
          const Positioned(
            left: -140,
            bottom: -120,
            child: _BrandOrb(size: 340, color: Color(0x1FD4A017)),
          ),
          child,
        ],
      ),
    );
  }
}

class _BrandOrb extends StatelessWidget {
  const _BrandOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class KhanyaLoadingView extends StatelessWidget {
  const KhanyaLoadingView({super.key, this.message = 'Preparing Khanya POS…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KhanyaBrandedBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const KhanyaLogo(height: 250, borderRadius: 0),
                    const SizedBox(height: 28),
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
