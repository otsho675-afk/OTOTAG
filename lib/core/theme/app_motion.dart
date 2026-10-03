import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Short, event-driven motion; no timers or repeating animations.
abstract final class AppMotion {
  static const interaction = Duration(milliseconds: 120);
  static const entrance = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}

/// Moves a cached child just eight pixels, once when mounted.
class AppEntrance extends StatelessWidget {
  const AppEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 8, end: 0),
      duration: AppMotion.entrance,
      curve: AppMotion.curve,
      builder: (_, offset, child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
      child: child,
    );
  }
}

/// Keeps InkWell's keyboard, focus, semantics and cancellation behavior.
class AppInteractiveSurface extends StatefulWidget {
  const AppInteractiveSurface({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color = Colors.transparent,
    this.side = BorderSide.none,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color color;
  final BorderSide side;

  @override
  State<AppInteractiveSurface> createState() => _AppInteractiveSurfaceState();
}

class _AppInteractiveSurfaceState extends State<AppInteractiveSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final surface = Material(
      color: widget.color,
      shape: RoundedRectangleBorder(
          borderRadius: widget.borderRadius, side: widget.side),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: widget.borderRadius,
        hoverColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: .05),
        focusColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: .10),
        highlightColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: .08),
        onHighlightChanged: (value) {
          if (_pressed != value) setState(() => _pressed = value);
        },
        child: widget.child,
      ),
    );
    if (reduced) return surface;
    return AnimatedScale(
      scale: _pressed && widget.onTap != null ? .985 : 1,
      duration: AppMotion.interaction,
      curve: AppMotion.curve,
      child: surface,
    );
  }
}

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder({this.native = false});
  final bool native;

  @override
  Duration get transitionDuration => AppMotion.entrance;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    if (native) {
      return const CupertinoPageTransitionsBuilder().buildTransitions(
          route, context, animation, secondaryAnimation, child);
    }
    final curved = animation.drive(CurveTween(curve: AppMotion.curve));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: curved.drive(
            Tween<Offset>(begin: const Offset(0, .015), end: Offset.zero)),
        child: child,
      ),
    );
  }
}
