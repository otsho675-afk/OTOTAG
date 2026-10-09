import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

/// One adaptive admin workspace: sidebar on desktop, drawer + bottom bar on
/// mobile. All destinations stay accessible at every screen size.
class AdminWorkspaceShell extends StatelessWidget {
  const AdminWorkspaceShell({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.child,
    required this.onRefresh,
    this.onSearch,
    this.pendingCount = 0,
    this.ticketCount = 0,
    this.loading = false,
  });

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
    'Ayarlar',
  ];

  static const icons = [
    Icons.space_dashboard_rounded,
    Icons.verified_user_outlined,
    Icons.groups_rounded,
    Icons.receipt_long_rounded,
    Icons.support_agent_rounded,
    Icons.system_update_alt_rounded,
    Icons.tune_rounded,
  ];

  static const descriptions = [
    'Özet ve hızlı işlemler',
    'Bekleyen başvurular',
    'Müşteri, usta ve firmalar',
    'Servis ve ilan geçmişi',
    'Destek ve şikâyetler',
    'Uygulama sürümleri',
    'Reklam, analiz ve güvenlik',
  ];

  static const _dark = Color(0xFF090E0D);
  static const _panel = Color(0xFF121A17);
  static const _mint = AppConstants.primaryColor;

  int _count(int index) => switch (index) {
        1 => pendingCount,
        4 => ticketCount,
        _ => 0,
      };

  Widget _navIcon(int index, {bool selected = false}) {
    final count = _count(index);
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: const Color(0xFFF5A524),
      textColor: Colors.black,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(
        icons[index],
        size: 21,
        color: selected ? _mint : const Color(0xFFB7C3BC),
      ),
    );
  }

  Widget _sidebar(BuildContext context,
      {required bool compact, required ValueChanged<int> navigate}) {
    final menu = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final active = selected == i;
      final item = Material(
        color: active ? _mint.withValues(alpha: 0.13) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: active
                ? _mint.withValues(alpha: .35)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => navigate(i),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 13 : 12, vertical: 13),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                _navIcon(i, selected: active),
                if (!compact) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                active ? FontWeight.w800 : FontWeight.w600,
                            color: active ? Colors.white : const Color(0xFFCDD5CF),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          descriptions[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF82948B)),
                        ),
                      ],
                    ),
                  ),
                  if (_count(i) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5A524).withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '${_count(i)}',
                        style: const TextStyle(
                          color: Color(0xFFF8C66A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
      menu.add(Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: compact
            ? Tooltip(message: labels[i], child: item)
            : item,
      ));
    }

    return Container(
      decoration: const BoxDecoration(
        color: _dark,
        border: Border(right: BorderSide(color: Color(0xFF27352E))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 18, 20, compact ? 12 : 18, 20),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _mint.withValues(alpha: .13),
                      border: Border.all(color: _mint.withValues(alpha: .35)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded,
                        color: _mint, size: 25),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('OTO TAG',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                                fontSize: 16,
                              )),
                          Text('YÖNETİM MERKEZİ',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF8DA69A),
                                letterSpacing: 1.1,
                              )),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!compact)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Text('ÇALIŞMA ALANI',
                    style: TextStyle(
                      color: Color(0xFF778980),
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12, vertical: 2),
                children: menu,
              ),
            ),
            if (!compact)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFF273D32)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: _mint, size: 19),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Güvenli yönetici oturumu',
                        style: TextStyle(
                          color: Color(0xFFDCE9DF), fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Icon(Icons.shield_outlined,
                    size: 20, color: Color(0xFF7D9A88)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 850;
          final expanded = constraints.maxWidth >= 1200;
          final mobile = !desktop;
          final scheme = Theme.of(context).colorScheme;
          final darkMode = Theme.of(context).brightness == Brightness.dark;

          return Scaffold(
            backgroundColor: darkMode
                ? const Color(0xFF0B110F)
                : const Color(0xFFF3F6F4),
            appBar: AppBar(
              toolbarHeight: mobile ? 68 : 76,
              surfaceTintColor: Colors.transparent,
              backgroundColor: darkMode
                  ? const Color(0xFF101815)
                  : Colors.white,
              elevation: 0,
              titleSpacing: mobile ? 0 : 22,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labels[selected],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      letterSpacing: -.4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    descriptions[selected],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: .6)),
                  ),
                ],
              ),
              actions: [
                if (onSearch != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: IconButton(
                      tooltip: 'Hızlı komut ve bölüm ara (Ctrl+K)',
                      onPressed: onSearch,
                      icon: const Icon(Icons.manage_search_rounded, size: 24),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton.filledTonal(
                    tooltip: 'Bu bölümün verilerini yenile',
                    onPressed: loading ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: .4),
                ),
              ),
            ),
            drawer: mobile
                ? Drawer(
                    width: constraints.maxWidth < 400
                        ? constraints.maxWidth * .88
                        : 310,
                    child: _sidebar(
                      context,
                      compact: false,
                      navigate: (index) {
                        Navigator.of(context).pop();
                        onSelect(index);
                      },
                    ),
                  )
                : null,
            body: SafeArea(
              top: false,
              bottom: false,
              child: Row(
                children: [
                  if (desktop)
                    SizedBox(
                      width: expanded ? 270 : 78,
                      child: _sidebar(
                        context,
                        compact: !expanded,
                        navigate: onSelect,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (loading)
                          const LinearProgressIndicator(
                              minHeight: 2, color: _mint),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: !mobile
                ? null
                : Builder(builder: (scaffoldContext) {
                    final destination = switch (selected) {
                      0 => 0,
                      2 => 1,
                      1 => 2,
                      _ => 3,
                    };
                    return NavigationBar(
                      height: 71,
                      selectedIndex: destination,
                      onDestinationSelected: (index) {
                        if (index == 3) {
                          Scaffold.of(scaffoldContext).openDrawer();
                        } else {
                          onSelect([0, 2, 1][index]);
                        }
                      },
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.space_dashboard_outlined),
                          selectedIcon: Icon(Icons.space_dashboard_rounded),
                          label: 'Genel',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.groups_outlined),
                          selectedIcon: Icon(Icons.groups_rounded),
                          label: 'Üyeler',
                        ),
                        NavigationDestination(
                          icon: _navIcon(1, selected: destination == 2),
                          label: 'Onaylar',
                        ),
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible: ticketCount > 0,
                            label: Text(ticketCount > 99
                                ? '99+'
                                : '$ticketCount'),
                            child: const Icon(Icons.grid_view_rounded),
                          ),
                          label: 'Bölümler',
                        ),
                      ],
                    );
                  }),
          );
        },
      );
}
