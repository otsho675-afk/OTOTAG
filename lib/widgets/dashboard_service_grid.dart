import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_palette.dart';
import '../core/theme/app_motion.dart';

class DashboardServiceGrid extends StatelessWidget {
  const DashboardServiceGrid({
    super.key,
    required this.services,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> services;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final light = Theme.of(context).brightness == Brightness.light;
        final columns = constraints.maxWidth >= 1000
            ? 5
            : constraints.maxWidth >= 680
                ? 3
                : 2;
        final double scale = MediaQuery.textScalerOf(context)
            .scale(1)
            .clamp(1.0, 3.0)
            .toDouble();
        final double cardHeight =
            (132.0 * scale).clamp(134.0, 300.0).toDouble();

        return AppEntrance(
          child: Column(
            children: [
              for (var first = 0; first < services.length; first += columns) ...[
                if (first > 0) const SizedBox(height: 12),
                Row(
                  children: [
                    for (var index = first;
                        index < services.length && index < first + columns;
                        index++) ...[
                      if (index > first) const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: cardHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: light ? .045 : .24),
                                blurRadius: 22,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: AppInteractiveSurface(
                            color: Theme.of(context).colorScheme.surface,
                            side: BorderSide(
                              color: light ? const Color(0xFFDCE5DE) : Colors.white.withValues(alpha: .065),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => onSelected(services[index]),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: light
                                            ? [Colors.white, const Color(0xFFFAFCFA)]
                                            : [
                                                AppConstants.cardElevated.withValues(alpha: .86),
                                                AppConstants.cardColor,
                                              ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  left: 18,
                                  right: 18,
                                  child: Container(
                                    height: 1,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          AppPalette.accent
                                              .withValues(alpha: light ? .24 : .46),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: -38,
                                  right: -30,
                                  child: Container(
                                    width: 112,
                                    height: 112,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          AppPalette.accent
                                              .withValues(alpha: .075),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(15),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  AppPalette.accentSoft,
                                                  AppPalette.accent
                                                      .withValues(alpha: .055),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: AppPalette.accentBorder,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppPalette.accent
                                                      .withValues(alpha: .06),
                                                  blurRadius: 14,
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              services[index]['icon']
                                                  as IconData,
                                              color: AppPalette.accent,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox.shrink(),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${services[index]['name']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          height: 1.12,
                                          letterSpacing: -.18,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Hizmeti görüntüle',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: light ? const Color(0xFF596B60) : AppConstants.subtleTextColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 10.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Icon(
                                            Icons.arrow_outward_rounded,
                                            color: AppPalette.accent,
                                            size: 13,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      });
}
