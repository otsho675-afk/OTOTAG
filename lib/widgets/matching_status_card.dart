import 'package:flutter/material.dart';
import '../core/theme/app_motion.dart';
import 'matching_radar.dart';

/// Search motion is isolated to a small canvas and respects reduced motion.
class MatchingStatusCard extends StatelessWidget {
  const MatchingStatusCard(
      {super.key,
      required this.title,
      required this.message,
      required this.icon,
      required this.stage,
      this.steps = const ['Talep', 'Teklif', 'Eşleşme'],
      this.active = true,
      this.searching = false,
      this.action});
  final String title, message;
  final IconData icon;
  final int stage;
  final List<String> steps;
  final bool active;
  final bool searching;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = active ? colors.primary : colors.onSurfaceVariant;
    final showSearch = searching && active && stage == 0;
    return RepaintBoundary(
        child: AppEntrance(
            child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .13),
              colors.surfaceContainerLow
            ]),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showSearch) ...[
          Center(
              child: MatchingRadar(color: accent, icon: icon, searching: true)),
          const SizedBox(height: 16),
          Center(
              child: Semantics(
                  liveRegion: true,
                  child: Text(title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)))),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.45)),
        ] else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.entrance),
                child: Container(
                    key: ValueKey(icon),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: accent, size: 28))),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Semantics(
                      liveRegion: true,
                      child: Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700))),
                  const SizedBox(height: 6),
                  Text(message,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.45)),
                ])),
          ]),
        const SizedBox(height: 22),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  AnimatedContainer(
                      duration: AppMotion.duration(context, AppMotion.entrance),
                      height: 4,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: active && i <= stage
                              ? accent
                              : colors.outlineVariant)),
                  const SizedBox(height: 8),
                  Text(steps[i],
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: active && i == stage
                              ? accent
                              : colors.onSurfaceVariant)),
                ])),
          ],
        ]),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]),
    )));
  }
}
