import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_motion.dart';

class AdminWorkspaceShell extends StatelessWidget {
  const AdminWorkspaceShell(
      {super.key,
      required this.selected,
      required this.onSelect,
      required this.child,
      required this.onRefresh,
      this.onSearch,
      this.pendingCount = 0,
      this.ticketCount = 0,
      this.loading = false});
  final int selected, pendingCount, ticketCount;
  final ValueChanged<int> onSelect;
  final VoidCallback onRefresh;
  final VoidCallback? onSearch;
  final Widget child;
  final bool loading;

  static const labels = [
    'Genel bakış',
    'Onaylar',
    'Üyeler',
    'İşlemler',
    'Destek',
    'Güncellemeler',
    'Ayarlar'
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.how_to_reg_outlined,
    Icons.people_outline,
    Icons.receipt_long_outlined,
    Icons.support_agent_outlined,
    Icons.system_update_outlined,
    Icons.settings_outlined
  ];
  static const descriptions = [
    'Sistem özeti ve hızlı erişim',
    'Usta ve firma başvuruları',
    'Müşteri, usta ve firma hesapları',
    'Servis talepleri ve parça ilanları',
    'Şikayetler ve çözüm takibi',
    'Android ve iPhone sürüm duyuruları',
    'Reklam, abonelik, analiz ve bakım'
  ];

  Widget _icon(int index) {
    final count = index == 1
        ? pendingCount
        : index == 4
            ? ticketCount
            : 0;
    return Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(icons[index]));
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Scaffold(
          appBar: AppBar(
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(labels[selected],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const Text('Ototag yönetim paneli',
                  style: TextStyle(fontSize: 11)),
            ]),
            actions: [
              if (onSearch != null)
                IconButton(
                    tooltip: 'Yönetimde ara (Ctrl+K)',
                    onPressed: onSearch,
                    icon: const Icon(Icons.search_rounded)),
              IconButton(
                  tooltip: 'Verileri yenile',
                  onPressed: loading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded))
            ],
          ),
          drawer: wide
              ? null
              : Drawer(
                  child: SafeArea(
                      child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Yönetim bölümleri',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700))),
                      for (var i = 0; i < labels.length; i++)
                        Builder(
                            builder: (drawerContext) => ListTile(
                                  selected: i == selected,
                                  leading: _icon(i),
                                  title: Text(labels[i]),
                                  subtitle: Text(descriptions[i]),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  onTap: () {
                                    Navigator.pop(drawerContext);
                                    onSelect(i);
                                  },
                                )),
                    ]))),
          body: SafeArea(
              top: false,
              bottom: false,
              child: Row(children: [
                if (wide) ...[
                  LayoutBuilder(
                      builder: (context, railConstraints) =>
                          SingleChildScrollView(
                              child: SizedBox(
                            height: math.max(railConstraints.maxHeight, 600),
                            child: NavigationRail(
                              extended: constraints.maxWidth >= 1100,
                              selectedIndex: selected,
                              onDestinationSelected: onSelect,
                              labelType: constraints.maxWidth >= 1100
                                  ? NavigationRailLabelType.none
                                  : NavigationRailLabelType.all,
                              destinations: [
                                for (var i = 0; i < labels.length; i++)
                                  NavigationRailDestination(
                                      icon: _icon(i), label: Text(labels[i]))
                              ],
                            ),
                          ))),
                  const VerticalDivider(width: 1),
                ],
                Expanded(child: child),
              ])),
          bottomNavigationBar: wide
              ? null
              : Builder(
                  builder: (scaffoldContext) => NavigationBar(
                        animationDuration:
                            AppMotion.duration(context, AppMotion.interaction),
                        selectedIndex: switch (selected) {
                          0 => 0,
                          2 => 1,
                          5 => 2,
                          _ => 3
                        },
                        onDestinationSelected: (value) {
                          if (value == 3) {
                            Scaffold.of(scaffoldContext).openDrawer();
                          } else {
                            onSelect([0, 2, 5][value]);
                          }
                        },
                        destinations: [
                          const NavigationDestination(
                              icon: Icon(Icons.dashboard_outlined),
                              label: 'Genel'),
                          const NavigationDestination(
                              icon: Icon(Icons.people_outline),
                              label: 'Üyeler'),
                          const NavigationDestination(
                              icon: Icon(Icons.system_update_outlined),
                              label: 'Güncelleme'),
                          NavigationDestination(
                              icon: Badge(
                                  isLabelVisible:
                                      pendingCount + ticketCount > 0,
                                  label: Text('${pendingCount + ticketCount}'),
                                  child: const Icon(Icons.menu_rounded)),
                              label: 'Bölümler'),
                        ],
                      )),
        );
      });
}
