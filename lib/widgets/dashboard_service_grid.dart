import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_motion.dart';

class DashboardServiceGrid extends StatelessWidget {
  const DashboardServiceGrid(
      {super.key, required this.services, required this.onSelected});
  final List<Map<String, dynamic>> services;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 5
            : constraints.maxWidth >= 680
                ? 3
                : 2;
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
        return AppEntrance(
            child: Column(children: [
          for (var first = 0; first < services.length; first += columns) ...[
            if (first > 0) const SizedBox(height: 10),
            Row(children: [
              for (var index = first;
                  index < services.length && index < first + columns;
                  index++) ...[
                if (index > first) const SizedBox(width: 10),
                Expanded(
                    child: SizedBox(
                  height: 82 * scale,
                  child: AppInteractiveSurface(
                    color: AppConstants.cardColor,
                    side: const BorderSide(color: AppConstants.borderColor),
                    onTap: () => onSelected(services[index]),
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                  color: AppConstants.primaryColor
                                      .withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(services[index]['icon'] as IconData,
                                  color: AppConstants.primaryColor, size: 22)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text('${services[index]['name']}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))),
                        ])),
                  ),
                )),
              ],
            ]),
          ],
        ]));
      });
}
