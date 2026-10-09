import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_motion.dart';

/// Animated nearby-provider scan. Only the radar repaint boundary animates.
/// Pauses in the background and honours system reduced-motion preferences.
class MatchingRadar extends StatefulWidget {
  const MatchingRadar({
    super.key,
    required this.color,
    required this.icon,
    required this.searching,
    this.size = 148,
  });
  final Color color;
  final IconData icon;
  final bool searching;
  final double size;

  @override
  State<MatchingRadar> createState() => _MatchingRadarState();
}

class _MatchingRadarState extends State<MatchingRadar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    final animate = widget.searching &&
        _foreground &&
        !AppMotion.reduced(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_motion.isAnimating) _motion.repeat();
    if (!animate && _motion.isAnimating) _motion.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant MatchingRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _RadarPainter(
              _motion,
              widget.color,
              widget.searching && !AppMotion.reduced(context),
              light,
            ),
            child: Center(
              child: Container(
                width: widget.size * .37,
                height: widget.size * .37,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface,
                  border: Border.all(
                    color: widget.color.withValues(alpha: light ? .25 : .55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: light ? .12 : .22),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon, color: widget.color, size: widget.size * .19,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.motion, this.color, this.searching, this.light)
      : super(repaint: motion);
  final Animation<double> motion;
  final Color color;
  final bool searching;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .46;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final ringAlpha = light ? .16 : .23;

    // Static concentric search zones + crosshair lines.
    for (final fraction in <double>[.48, .72, 1]) {
      base.color = color.withValues(alpha: ringAlpha);
      canvas.drawCircle(center, radius * fraction, base);
    }
    final crosshair = Paint()
      ..color = color.withValues(alpha: light ? .08 : .13)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy), crosshair);
    canvas.drawLine(Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius), crosshair);

    final angle = motion.value * math.pi * 2;
    if (searching) {
      // Translucent rotating sector and a crisp sweeping edge.
      final sweepRect = Rect.fromCircle(center: center, radius: radius);
      final sector = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: .02),
            color.withValues(alpha: light ? .20 : .28),
          ],
          stops: const [0, .58, 1],
          transform: GradientRotation(angle),
        ).createShader(sweepRect);
      canvas.drawCircle(center, radius, sector);
      final arm = Paint()
        ..color = color.withValues(alpha: .72)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center,
          Offset(center.dx + math.cos(angle) * radius,
              center.dy + math.sin(angle) * radius), arm);

      final pulse = (motion.value * 2) % 1;
      canvas.drawCircle(
        center,
        radius * (.48 + .52 * pulse),
        Paint()
          ..color = color.withValues(alpha: .32 * (1 - pulse))
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // Abstract potential providers; decoration, not actual geolocated results.
    final dots = <Offset>[
      Offset(center.dx + radius * .63, center.dy - radius * .39),
      Offset(center.dx - radius * .67, center.dy + radius * .23),
      Offset(center.dx + radius * .22, center.dy + radius * .79),
    ];
    for (var i = 0; i < dots.length; i++) {
      final blink = searching
          ? .55 + .45 * math.sin(angle - i * 1.8).abs()
          : .8;
      canvas.drawCircle(dots[i], 5.5,
        Paint()..color = color.withValues(alpha: .10 * blink));
      canvas.drawCircle(dots[i], 2.8,
        Paint()..color = color.withValues(alpha: .85 * blink));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.color != color ||
      oldDelegate.searching != searching ||
      oldDelegate.light != light;
}
