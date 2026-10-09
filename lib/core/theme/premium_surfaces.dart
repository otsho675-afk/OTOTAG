import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'app_motion.dart';

/// OTO TAG'in kurumsal ekranlarında kullanılan hafif, performans dostu arka plan.
/// Sürekli animasyon kullanmaz; girişte yalnızca tek seferlik AppEntrance uygulanabilir.
class PremiumScene extends StatelessWidget {
  const PremiumScene({
    super.key,
    required this.child,
    this.showGrid = true,
    this.accentStrength = 1,
  });

  final Widget child;
  final bool showGrid;
  final double accentStrength;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final double strength = accentStrength.clamp(0.0, 1.4).toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: light ? const Color(0xFFF6F9F6) : AppConstants.bgColor),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  light ? const Color(0xFFFFFFFF) : AppConstants.bgElevated.withValues(alpha: .88),
                  light ? const Color(0xFFF4F9F5) : AppConstants.bgColor,
                  light ? const Color(0xFFEBF4ED) : const Color(0xFF020403),
                ],
                stops: const [0, .48, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: -size.width * .48,
          right: -size.width * .32,
          child: IgnorePointer(
            child: Container(
              width: size.width * 1.28,
              height: size.width * 1.28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppConstants.primaryColor
                        .withValues(alpha: .105 * strength),
                    AppConstants.primaryDeep
                        .withValues(alpha: .035 * strength),
                    Colors.transparent,
                  ],
                  stops: const [0, .38, .75],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -size.width * .52,
          left: -size.width * .44,
          child: IgnorePointer(
            child: Container(
              width: size.width * 1.05,
              height: size.width * 1.05,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (light ? const Color(0xFF08784D) : Colors.white).withValues(alpha: .025),
                    AppConstants.primaryColor
                        .withValues(alpha: .018 * strength),
                    Colors.transparent,
                  ],
                  stops: const [0, .38, .76],
                ),
              ),
            ),
          ),
        ),
        if (showGrid)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: .52,
                child: CustomPaint(painter: _CorporateGridPainter()),
              ),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class PremiumGlassPanel extends StatelessWidget {
  const PremiumGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
    this.blur = 16,
    this.accent = false,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final bool accent;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? .09 : .34),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          if (accent)
            BoxShadow(
              color: AppConstants.primaryColor.withValues(alpha: .045),
              blurRadius: 34,
              spreadRadius: 1,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  light ? Colors.white : const Color(0xFF171A1F).withValues(alpha: .94),
                  light ? const Color(0xFFF8FBF8) : const Color(0xFF0D0F13).withValues(alpha: .91),
                ],
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: accent
                    ? AppConstants.primaryColor.withValues(alpha: .22)
                    : (light ? const Color(0xFFC8DDCE) : Colors.white.withValues(alpha: .075)),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class PremiumBrandMark extends StatelessWidget {
  const PremiumBrandMark({
    super.key,
    this.size = 58,
    this.icon = Icons.directions_car_filled_rounded,
  });

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppConstants.primaryColor.withValues(alpha: .19),
            AppConstants.primaryDeep.withValues(alpha: .055),
          ],
        ),
        borderRadius: BorderRadius.circular(size * .30),
        border: Border.all(
          color: AppConstants.primaryColor.withValues(alpha: .24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryColor.withValues(alpha: .08),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: AppConstants.primaryColor,
        size: size * .48,
      ),
    );
  }
}

class PremiumStatusPill extends StatelessWidget {
  const PremiumStatusPill(
    this.label, {
    super.key,
    this.icon,
    this.accent = true,
  });

  final String label;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final color = accent
      ? (light ? const Color(0xFF08784D) : AppConstants.primaryColor)
      : Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: accent ? .085 : .055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .55,
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumSectionHeading extends StatelessWidget {
  const PremiumSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: subtitle == null ? 24 : 34,
          decoration: BoxDecoration(
            gradient: AppConstants.brandGradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryColor.withValues(alpha: .18),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppConstants.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppConstants.mutedColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class PremiumMetric extends StatelessWidget {
  const PremiumMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.white.withValues(alpha: .028),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppConstants.primaryColor, size: 15),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppConstants.textColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppConstants.subtleTextColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PremiumHairline extends StatelessWidget {
  const PremiumHairline({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            AppConstants.primaryColor.withValues(alpha: .24),
            Colors.white.withValues(alpha: .08),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class PremiumEntrance extends StatelessWidget {
  const PremiumEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AppEntrance(child: child);
}

class _CorporateGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 44.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .017)
      ..strokeWidth = .7;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final accentPaint = Paint()
      ..color = AppConstants.primaryColor.withValues(alpha: .014)
      ..strokeWidth = 1;
    for (double x = step * 4; x <= size.width; x += step * 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
