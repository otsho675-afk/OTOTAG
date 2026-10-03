import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_motion.dart';

/// Only this small canvas repaints; the surrounding screen stays cached.
class MatchingRadar extends StatefulWidget {
  const MatchingRadar(
      {super.key,
      required this.color,
      required this.icon,
      required this.searching});
  final Color color;
  final IconData icon;
  final bool searching;
  @override
  State<MatchingRadar> createState() => _MatchingRadarState();
}

class _MatchingRadarState extends State<MatchingRadar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));
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
    if (!animate) _motion.stop();
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
  Widget build(BuildContext context) => ExcludeSemantics(
      child: RepaintBoundary(
          child: SizedBox.square(
              dimension: 100,
              child: CustomPaint(
                painter: _RadarPainter(_motion, widget.color,
                    widget.searching && !AppMotion.reduced(context)),
                child: Center(
                    child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                                color: widget.color.withValues(alpha: .5))),
                        child:
                            Icon(widget.icon, color: widget.color, size: 26))),
              ))));
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.motion, this.color, this.searching)
      : super(repaint: motion);
  final Animation<double> motion;
  final Color color;
  final bool searching;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final fraction in [.68, 1.0]) {
      paint.color = color.withValues(alpha: .14);
      canvas.drawCircle(center, radius * fraction, paint);
    }
    if (searching) {
      paint.color = color.withValues(alpha: .6 * (1 - motion.value));
      canvas.drawCircle(center, radius * (.6 + .4 * motion.value), paint);
      paint.color = color.withValues(alpha: .8);
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          motion.value * math.pi * 2,
          math.pi / 3,
          false,
          paint..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.searching != searching ||
      oldDelegate.motion != motion;
}
