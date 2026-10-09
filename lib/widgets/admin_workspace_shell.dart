import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';

/// OTO TAG admin console. One navigation model across phone, tablet and web.
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

  static const labels = <String>[
    'Genel bakış', 'Onaylar', 'Üyeler', 'İşlemler',
    'Destek', 'Güncellemeler', 'Ayarlar',
  ];
  static const icons = <IconData>[
    Icons.grid_view_rounded, Icons.verified_user_outlined,
    Icons.people_alt_outlined, Icons.receipt_long_outlined,
    Icons.support_agent_outlined, Icons.system_update_alt_rounded,
    Icons.tune_rounded,
  ];
  static const descriptions = <String>[
    'Sistem özeti ve hızlı erişim',
    'Usta ve firma başvuruları',
    'Müşteri, usta ve firma hesapları',
    'Servis talepleri ve parça ilanları',
    'Şikâyetler ve çözüm takibi',
    'Android ve iPhone sürüm duyuruları',
    'Reklam, abonelik, analiz ve bakım',
  ];
  static const Color _ink = Color(0xFF08120E);
  static const Color _side = Color(0xFF0D1914);
  static const Color _surface = Color(0xFF14231C);
  static const Color _line = Color(0xFF26382E);
  static const Color _text = Color(0xFFF2FAF4);
  static const Color _sub = Color(0xFF92AA9A);
  static const Color _mint = AppConstants.primaryColor;

  int _badgeCount(int index) => switch (index) {
        1 => pendingCount,
        4 => ticketCount,
        _ => 0,
      };

  String _counter(int value) => value > 99 ? '99+' : '$value';

  Widget _mark({double size = 42}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF00FFA3), Color(0xFF00A86D)],
          ),
          borderRadius: BorderRadius.circular(size * .31),
          boxShadow: [
            BoxShadow(color: _mint.withValues(alpha: .14), blurRadius: 18),
          ],
        ),
        child: Icon(Icons.route_rounded, color: _ink, size: size * .55),
      );

  Widget _navTile(int index, {required bool compact, required VoidCallback onTap}) {
    final active = selected == index;
    final count = _badgeCount(index);
    final badge = count > 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: active ? _mint : const Color(0xFF344139),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_counter(count),
                style: TextStyle(
                  color: active ? _ink : _text,
                  fontSize: 10, fontWeight: FontWeight.w900,
                )),
          )
        : null;
    final icon = Icon(icons[index],
        size: compact ? 21 : 22,
        color: active ? _mint : const Color(0xFFB4C7B9));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: active ? const Color(0xFF1C382A) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 58 : 56),
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 7 : 13, vertical: compact ? 8 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? _mint.withValues(alpha: .32) : Colors.transparent,
              ),
            ),
            child: compact
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Stack(clipBehavior: Clip.none, children: [
                      icon,
                      if (count > 0)
                        const Positioned(
                          top: -5, right: -9,
                          child: CircleAvatar(
                            radius: 5,
                            backgroundColor: Color(0xFFF7B84B),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 5),
                    Text(labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: active ? _mint : _sub,
                          fontSize: 10, fontWeight: FontWeight.w700,
                        )),
                  ])
                : Row(children: [
                    Container(
                      width: 35, height: 35,
                      decoration: BoxDecoration(
                        color: active
                            ? _mint.withValues(alpha: .13)
                            : const Color(0xFF1A2A21),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: icon),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(labels[index],
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active ? _text : const Color(0xFFDEE9E0),
                              fontSize: 13, fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(height: 2),
                        Text(descriptions[index],
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: _sub)),
                      ],
                    )),
                    if (badge != null) ...[
                      const SizedBox(width: 7), badge,
                    ] else if (active)
                      const Icon(Icons.chevron_right_rounded,
                          color: _mint, size: 19),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, {bool compact = false}) {
    if (compact) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(label,
          style: const TextStyle(
            color: _sub, fontWeight: FontWeight.w800,
            fontSize: 10, letterSpacing: 1.7,
          )),
    );
  }

  Widget _navigation(BuildContext context, {
    required bool compact,
    required bool inDrawer,
    required ValueChanged<int> navigate,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: _side,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 9 : 17, 19, compact ? 9 : 17, 15),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                _mark(size: compact ? 42 : 44),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OTO TAG',
                          style: TextStyle(
                            color: _text, fontSize: 17,
                            fontWeight: FontWeight.w900, letterSpacing: 1,
                          )),
                      Text('YÖNETİM MERKEZİ',
                          style: TextStyle(
                            color: _mint, fontSize: 10,
                            fontWeight: FontWeight.w800, letterSpacing: 1.25,
                          )),
                    ],
                  )),
                  if (inDrawer)
                    IconButton(
                      tooltip: 'Menüyü kapat',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: _text),
                    ),
                ],
              ],
            ),
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 3, 16, 9),
              child: Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _line),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                child: const Row(children: [
                  Icon(Icons.shield_rounded, color: _mint, size: 19),
                  SizedBox(width: 9),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yönetici erişimi',
                          style: TextStyle(color: _text,
                              fontWeight: FontWeight.w800, fontSize: 11)),
                      Text('OTO TAG kontrol merkezi',
                          style: TextStyle(color: _sub, fontSize: 10)),
                    ],
                  )),
                  Icon(Icons.verified_rounded,
                      color: _mint, size: 17),
                ]),
              ),
            ),
          const Divider(color: _line, thickness: 1, height: 12),
          Expanded(child: ListView(
            padding: EdgeInsets.fromLTRB(
                compact ? 8 : 13, 0, compact ? 8 : 13, 14),
            children: [
              _sectionLabel('OPERASYON', compact: compact),
              for (final index in [0, 1, 2, 3, 4])
                _navTile(index, compact: compact,
                    onTap: () => navigate(index)),
              _sectionLabel('SİSTEM', compact: compact),
              for (final index in [5, 6])
                _navTile(index, compact: compact,
                    onTap: () => navigate(index)),
            ],
          )),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 8, 15, 19),
              child: Row(children: [
                Container(width: 8, height: 8,
                    decoration: const BoxDecoration(
                        color: _mint, shape: BoxShape.circle)),
                const SizedBox(width: 9),
                const Expanded(child: Text('Yönetim paneli',
                    style: TextStyle(color: _sub, fontSize: 11))),
                const Text('OTO TAG',
                    style: TextStyle(
                        color: _sub, fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
        ]),
      ),
    );
  }

  /// Mobile section picker replaces the full-width drawer with a compact grid.
  Future<void> _showSectionsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _side,
      constraints: const BoxConstraints(maxWidth: 540),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  _mark(size: 37),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yönetim bölümleri',
                        style: TextStyle(
                          color: _text, fontSize: 19,
                          fontWeight: FontWeight.w900,
                        )),
                      Text('Bir bölüme dokunarak doğrudan açın',
                        style: TextStyle(color: _sub, fontSize: 11)),
                    ],
                  )),
                  IconButton(
                    tooltip: 'Menüyü kapat',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded, color: _text),
                  ),
                ]),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: labels.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 84,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (ctx, index) {
                    final active = selected == index;
                    return Material(
                      color: active ? const Color(0xFF1D3A2A) : _surface,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onSelect(index);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: active
                                  ? _mint.withValues(alpha: .5) : _line,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(icons[index], color: _mint, size: 21),
                                const Spacer(),
                                if (_badgeCount(index) > 0)
                                  Text(_counter(_badgeCount(index)),
                                    style: const TextStyle(color: _mint,
                                      fontSize: 12, fontWeight: FontWeight.w900)),
                              ]),
                              const Spacer(),
                              Text(labels[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _text,
                                    fontSize: 13, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Five priority destinations stay reachable with one tap on phones.
  Widget _mobileTabs(BuildContext context) {
    final active = switch (selected) {
      0 => 0, 1 => 1, 2 => 2, 5 => 3, _ => 4,
    };
    const items = <(String, IconData, IconData)>[
      ('Genel', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
      ('Başvuru', Icons.fact_check_outlined, Icons.fact_check_rounded),
      ('Üyeler', Icons.groups_outlined, Icons.groups_rounded),
      ('Güncelleme', Icons.system_update_alt_outlined, Icons.system_update_alt_rounded),
      ('Bölümler', Icons.widgets_outlined, Icons.widgets_rounded),
    ];
    return SafeArea(top: false, child: Container(
      decoration: const BoxDecoration(color: _side,
        border: Border(top: BorderSide(color: _line))),
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 3),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: active == i ? const Color(0xFF1B3D2A) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  if (i == 4) {
                    _showSectionsSheet(context);
                  } else {
                    onSelect([0, 1, 2, 5][i]);
                  }
                },
                child: SizedBox(height: 54, child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Icon(active == i ? items[i].$3 : items[i].$2,
                        color: active == i ? _mint : _sub, size: 22),
                      if ((i == 1 && pendingCount > 0) ||
                          (i == 4 && ticketCount > 0))
                        Positioned(right: -9, top: -5, child: Container(
                          width: 10, height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF4B95C), shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: _side, width: 1.5)),
                          ),
                        )),
                    ]),
                    const SizedBox(height: 5),
                    Text(items[i].$1, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active == i ? _mint : _sub,
                        fontSize: 10,
                        fontWeight: active == i ? FontWeight.w900 : FontWeight.w700,
                      )),
                  ],
                )),
              ),
            ),
          )),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final desktop = width >= 760;
      final expanded = width >= 1080;
      final mobile = !desktop;
      final selectedTitle = labels[selected];
      return Scaffold(
        backgroundColor: const Color(0xFF0B120F),

        appBar: AppBar(
          foregroundColor: _text,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: mobile ? 70 : 79,
          backgroundColor: _ink,
          automaticallyImplyLeading: false,
          leading: mobile
              ? IconButton(
                  tooltip: 'Yönetim bölümleri',
                  onPressed: () => _showSectionsSheet(context),
                  icon: const Icon(Icons.dashboard_customize_outlined,
                      color: _mint, size: 23),
                )
              : null,
          titleSpacing: mobile ? 0 : 20,
          title: Row(children: [
            if (!mobile) ...[
              Container(width: 4, height: 34,
                  decoration: BoxDecoration(
                    color: _mint, borderRadius: BorderRadius.circular(5))),
              const SizedBox(width: 12),
            ],
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selectedTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _text, fontWeight: FontWeight.w900,
                    fontSize: mobile ? 18 : 22, letterSpacing: -.6,
                  )),
                const SizedBox(height: 3),
                Text(mobile ? 'OTO TAG  /  ADMIN' : descriptions[selected],
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _sub, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: .7,
                  )),
              ],
            )),
          ]),
          actions: [
            if (onSearch != null)
              if (width >= 1190)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: OutlinedButton.icon(
                    onPressed: onSearch,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _line),
                      backgroundColor: _surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 15),
                    ),
                    icon: const Icon(Icons.search_rounded, color: _mint, size: 19),
                    label: const Text('Yönetimde ara    Ctrl + K',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Yönetimde ara',
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded, size: 23),
                ),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 1),
              child: IconButton(
                tooltip: 'Verileri yenile',
                onPressed: loading ? null : onRefresh,
                style: IconButton.styleFrom(
                  backgroundColor: _surface,
                  foregroundColor: _mint,
                  minimumSize: const Size(42, 42),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 21),
              ),
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: SizedBox(height: 1,
              child: ColoredBox(color: _line)),
          ),
        ),
        body: SafeArea(
          top: false, bottom: false,
          child: Row(children: [
            if (desktop)
              SizedBox(
                width: expanded ? 254 : 87,
                child: _navigation(context,
                  compact: !expanded, inDrawer: false,
                  navigate: onSelect),
              ),
            Expanded(child: Column(children: [
              if (loading)
                const LinearProgressIndicator(
                  minHeight: 2, color: _mint),
              Expanded(child: child),
            ])),
          ]),
        ),
        bottomNavigationBar: mobile ? _mobileTabs(context) : null,
      );
    },
  );
}
