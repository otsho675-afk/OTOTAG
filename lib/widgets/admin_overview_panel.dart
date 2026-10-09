import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_command_palette.dart';
import '../core/constants/app_constants.dart';

/// Data-driven command center. Every shortcut performs an existing admin action.
class AdminOverviewPanel extends StatelessWidget {
  const AdminOverviewPanel({
    super.key,
    required this.revenue,
    required this.completedJobs,
    required this.customers,
    required this.providers,
    required this.companies,
    required this.pending,
    required this.tickets,
    required this.jobs,
    required this.commands,
    required this.onCommand,
    required this.onJob,
    required this.onTicket,
    required this.serviceLabel,
    required this.statusLabel,
    this.dashboardReady = true,
    this.ticketsReady = true,
    this.footer = const SizedBox.shrink(),
  });

  final double revenue;
  final int completedJobs, customers, providers, companies;
  final List<Map<String, dynamic>> pending, tickets, jobs;
  final List<AdminCommand> commands;
  final ValueChanged<String> onCommand;
  final ValueChanged<Map<String, dynamic>> onJob, onTicket;
  final String Function(String?) serviceLabel, statusLabel;
  final bool dashboardReady, ticketsReady;
  final Widget footer;

  static const _bg = Color(0xFF0B120F);
  static const _card = Color(0xFF142019);
  static const _card2 = Color(0xFF192720);
  static const _stroke = Color(0xFF2A3D32);
  static const _white = Color(0xFFF2FAF5);
  static const _muted = Color(0xFFA1B5A7);
  static const _mint = AppConstants.primaryColor;

  String _money(double value) =>
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(value);

  @override
  Widget build(BuildContext context) {
    final open = tickets.where((t) => t['status'] == 'open').toList();
    return LayoutBuilder(builder: (context, dimensions) {
      final horizontal = dimensions.maxWidth >= 1000 ? 28.0 : 14.0;
      return ColoredBox(
        color: _bg,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(horizontal, 17, horizontal, 46),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hero(context, pendingCount: pending.length,
                      openCount: open.length),
                  const SizedBox(height: 13),
                  _shortcutGrid(context, pendingCount: pending.length,
                      openCount: open.length),
                  const SizedBox(height: 23),
                  _sectionHeader('CANLI GÖRÜNÜM', 'İşletme özeti',
                      'Veriler mevcut sunucu kayıtlarından alınır.'),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1000
                        ? 3 : constraints.maxWidth >= 290 ? 2 : 1;
                    final cardWidth =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      _metric(cardWidth, 'Servis cirosu',
                          dashboardReady ? _money(revenue) : '—',
                          'Son 30 gün · tamamlanan işler',
                          Icons.account_balance_wallet_outlined,
                          () => onCommand('section:3')),
                      _metric(cardWidth, 'Tamamlanan servis',
                          dashboardReady ? '$completedJobs' : '—',
                          'Son 30 gün', Icons.task_alt_rounded,
                          () => onCommand('section:3')),
                      _metric(cardWidth, 'Müşteriler',
                          dashboardReady ? '$customers' : '—',
                          'Kayıtlı müşteri hesapları',
                          Icons.person_outline_rounded,
                          () => onCommand('customers')),
                      _metric(cardWidth, 'Ustalar',
                          dashboardReady ? '$providers' : '—',
                          'Kayıtlı usta hesapları',
                          Icons.handyman_outlined,
                          () => onCommand('providers')),
                      _metric(cardWidth, 'Firmalar',
                          dashboardReady ? '$companies' : '—',
                          'Rent a Car işletmeleri',
                          Icons.business_outlined,
                          () => onCommand('companies')),
                      _metric(cardWidth, 'Açık destek',
                          ticketsReady ? '${open.length}' : '—',
                          'İncelenmesi gereken talepler',
                          Icons.support_agent_outlined,
                          () => onCommand('section:4')),
                    ]);
                  }),
                  const SizedBox(height: 28),
                  _sectionHeader('İŞ SIRASI', 'Öncelikli işlemler',
                      'Dikkat isteyen kayıtlar ve doğrudan bağlantılar.'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 9, runSpacing: 9, children: [
                    _actionChip(
                      Icons.how_to_reg_outlined,
                      dashboardReady
                          ? '${pending.length} başvuru bekliyor'
                          : 'Başvurular alınamadı',
                      () => onCommand('section:1')),
                    _actionChip(
                      Icons.forum_outlined,
                      ticketsReady
                          ? '${open.length} açık destek talebi'
                          : 'Destek verisi alınamadı',
                      () => onCommand('section:4')),
                    _actionChip(
                      Icons.car_rental_outlined,
                      dashboardReady
                          ? '$companies kiralama firması'
                          : 'Firma verisi alınamadı',
                      () => onCommand('companies')),
                  ]),
                  const SizedBox(height: 14),
                  if (pending.isNotEmpty || open.isNotEmpty)
                    LayoutBuilder(builder: (context, constraints) {
                      final sideBySide = constraints.maxWidth >= 800;
                      final pendingCard = _priorityCard(
                        title: 'Başvuru inceleme',
                        icon: Icons.verified_user_outlined,
                        count: pending.length,
                        onAll: () => onCommand('section:1'),
                        children: [
                          for (final person in pending.take(3))
                            _rowTile(
                              name: '${person['name'] ?? 'Başvuru'}',
                              info: person['user_type'] == 'rentacar'
                                  ? 'Kiralama firması · Belgeleri incele'
                                  : '${serviceLabel(person['service_category']?.toString())} · Belgeleri incele',
                              icon: Icons.person_outline_rounded,
                              onTap: () => onCommand('section:1'),
                            ),
                          if (pending.isEmpty)
                            _emptyMini('Bekleyen başvuru bulunmuyor.'),
                        ]);
                      final ticketCard = _priorityCard(
                        title: 'Destek talepleri',
                        icon: Icons.headset_mic_outlined,
                        count: open.length,
                        onAll: () => onCommand('section:4'),
                        children: [
                          for (final item in open.take(3))
                            _rowTile(
                              name: '${item['subject'] ?? 'Destek talebi'}',
                              info: 'Talep #${item['id']}',
                              icon: Icons.chat_bubble_outline_rounded,
                              onTap: () => onTicket(item),
                            ),
                          if (open.isEmpty)
                            _emptyMini('Açık destek talebi bulunmuyor.'),
                        ]);
                      return sideBySide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: pendingCard),
                                const SizedBox(width: 12),
                                Expanded(child: ticketCard),
                              ])
                          : Column(children: [
                              pendingCard, const SizedBox(height: 12),
                              ticketCard,
                            ]);
                    })
                  else if (dashboardReady && ticketsReady)
                    _emptyMini('Bekleyen başvuru veya açık destek talebi yok.'),
                  const SizedBox(height: 28),
                  _sectionHeader('YÖNETİM ARAÇLARI', 'Hızlı erişim',
                      'Sık kullanılan işlemlere tek dokunuşla ulaşın.'),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1020
                        ? 3 : constraints.maxWidth >= 680 ? 2 : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final command in commands)
                        SizedBox(width: width,
                          child: _quickCommand(
                            title: command.title,
                            detail: command.subtitle,
                            icon: command.icon,
                            onTap: () => onCommand(command.id),
                          )),
                    ]);
                  }),
                  const SizedBox(height: 28),
                  _sectionHeader('HAREKETLER', 'Son servis talepleri',
                      'Sunucudaki en güncel 100 kaydın son 5 tanesi.',
                      action: 'Tümünü gör',
                      onTap: () => onCommand('section:3')),
                  const SizedBox(height: 12),
                  Container(
                    decoration: _surfaceDecoration(),
                    child: jobs.isEmpty
                        ? _emptyMini(dashboardReady
                            ? 'Henüz servis talebi bulunmuyor.'
                            : 'Servis verisi alınamadı.')
                        : Column(children: [
                            for (final job in jobs.take(5))
                              _rowTile(
                                name: '#${job['id']} · ${serviceLabel(job['service_type']?.toString())}',
                                info: '${job['customer_name'] ?? 'Müşteri'} · ${statusLabel(job['status']?.toString())}',
                                icon: Icons.receipt_long_outlined,
                                onTap: () => onJob(job),
                              ),
                          ]),
                  ),
                  const SizedBox(height: 18),
                  footer,
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  BoxDecoration _surfaceDecoration() => BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(19),
    border: Border.all(color: _stroke),
  );

  Widget _hero(BuildContext context,
      {required int pendingCount, required int openCount}) {
    final total = customers + providers + companies;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1C3D2C), Color(0xFF10231A), Color(0xFF0C1812)],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFF32634A)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .16),
              blurRadius: 25, offset: const Offset(0, 10)),
        ],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 750;
        if (!wide) {
          return _mobileHero(context, total,
              pendingCount: pendingCount, openCount: openCount);
        }
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 31, height: 31,
                decoration: BoxDecoration(
                    color: _mint.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.tune_rounded, color: _mint, size: 18),
              ),
              const SizedBox(width: 9),
              const Expanded(child: Text('OTO TAG   /   CONTROL CENTER',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10, color: _mint,
                    fontWeight: FontWeight.w900, letterSpacing: 1.1,
                  ))),
            ]),
            const SizedBox(height: 16),
            const Text('Yönetim merkezi',
                maxLines: 2,
                style: TextStyle(
                  color: _white, fontSize: 27,
                  fontWeight: FontWeight.w900, letterSpacing: -.8,
                )),
            const SizedBox(height: 6),
            const Text('Tüm operasyonları tek ekrandan yönetin.',
                style: TextStyle(color: Color(0xFFB9D1C2), fontSize: 13)),
            const SizedBox(height: 17),
            Wrap(spacing: 9, runSpacing: 9, children: [
              _heroPill(Icons.verified_user_rounded,
                  dashboardReady ? '$pendingCount başvuru' : 'Başvuru bilgisi yok',
                  () => onCommand('section:1')),
              _heroPill(Icons.chat_outlined,
                  ticketsReady ? '$openCount destek' : 'Destek bilgisi yok',
                  () => onCommand('section:4')),
            ]),
          ],
        );
        final totalPanel = Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF091C12).withValues(alpha: .74),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: const Color(0xFF326349)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TOPLAM ÜYE',
                  style: TextStyle(
                    color: _muted, fontSize: 10,
                    fontWeight: FontWeight.w800, letterSpacing: 1.3)),
              const SizedBox(height: 8),
              Text(dashboardReady ? NumberFormat.decimalPattern('tr_TR').format(total) : '—',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _mint, fontSize: 34,
                    fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(height: 4),
              const Text('Müşteri, usta ve firmalar',
                  style: TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 15),
              SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => onCommand('section:2'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  label: const Text('Üyeleri yönet'),
                )),
            ],
          ),
        );
        return Padding(
          padding: EdgeInsets.all(wide ? 25 : 19),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: left),
                  const SizedBox(width: 25),
                  SizedBox(width: 250, child: totalPanel),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    left, const SizedBox(height: 17),
                    totalPanel,
                  ]),
        );
      }),
    );
  }

  /// Compact mobile header so essential actions remain visible above the fold.
  Widget _mobileHero(BuildContext context, int total,
      {required int pendingCount, required int openCount}) {
    return Padding(
      padding: const EdgeInsets.all(17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _mint.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _mint.withValues(alpha: .28)),
                ),
                child: const Text('OTO TAG  ·  YENİ PANEL',
                  style: TextStyle(color: _mint, fontSize: 9,
                      fontWeight: FontWeight.w900, letterSpacing: .8)),
              ),
              const SizedBox(height: 10),
              const Text('Yönetim merkezi',
                  maxLines: 2,
                  style: TextStyle(color: _white, fontSize: 21,
                      fontWeight: FontWeight.w900, letterSpacing: -.6)),
              const SizedBox(height: 4),
              const Text('Kontrol sende. Tüm işlemler tek yerde.',
                  maxLines: 2,
                  style: TextStyle(color: _muted, fontSize: 11)),
            ],
          )),
          const SizedBox(width: 9),
          Container(
            width: 87, height: 96,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF081910),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF326349)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(dashboardReady
                    ? NumberFormat.decimalPattern('tr_TR').format(total)
                    : '—',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _mint, fontSize: 26,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                const Text('TOPLAM ÜYE',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ]),
          ),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: _mobileHeroLink(
              Icons.verified_outlined,
              dashboardReady ? '${pendingCount} onay' : 'Onaylar',
              () => onCommand('section:1'))),
          const SizedBox(width: 9),
          Expanded(child: _mobileHeroLink(
              Icons.support_agent_outlined,
              ticketsReady ? '${openCount} destek' : 'Destek',
              () => onCommand('section:4'))),
        ]),
      ]),
    );
  }

  Widget _mobileHeroLink(IconData icon, String title, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(children: [
            Icon(icon, color: _mint, size: 17),
            const SizedBox(width: 7),
            Expanded(child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _white,
                    fontSize: 11, fontWeight: FontWeight.w800))),
            const Icon(Icons.north_east_rounded, color: _mint, size: 14),
          ]),
        ),
      ),
    );
  }

  /// Four high-use routes are never hidden behind long metric lists.
  Widget _shortcutGrid(BuildContext context,
      {required int pendingCount, required int openCount}) {
    const shortcuts = <(String, IconData, String)>[
      ('Üyeler', Icons.people_alt_rounded, 'section:2'),
      ('Onaylar', Icons.verified_user_rounded, 'section:1'),
      ('İşlemler', Icons.receipt_long_rounded, 'section:3'),
      ('Destek', Icons.support_agent_rounded, 'section:4'),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final count = constraints.maxWidth >= 800 ? 4 : 2;
      final width = (constraints.maxWidth - (count - 1) * 10) / count;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < shortcuts.length; i++)
          SizedBox(
            width: width,
            child: Material(
              color: _card2,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onCommand(shortcuts[i].$3),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: _stroke),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Container(
                      width: 33, height: 33,
                      decoration: BoxDecoration(
                        color: _mint.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(shortcuts[i].$2, color: _mint, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(shortcuts[i].$1,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _white,
                            fontSize: 12, fontWeight: FontWeight.w800))),
                    if (constraints.maxWidth >= 530 &&
                        (i == 1 || i == 3))
                      Text(i == 1 ? '$pendingCount' : '$openCount',
                          style: const TextStyle(color: _mint,
                              fontSize: 12, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }

  Widget _heroPill(IconData icon, String label, VoidCallback onTap) =>
      Material(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: _mint, size: 16),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _white, fontWeight: FontWeight.w800, fontSize: 11))),
              const SizedBox(width: 7),
              const Icon(Icons.north_east, color: _mint, size: 13),
            ]),
          ),
        ),
      );

  Widget _sectionHeader(String eyebrow, String title, String description,
      {String? action, VoidCallback? onTap}) =>
    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow,
              style: const TextStyle(color: _mint,
                  fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 1.3)),
          const SizedBox(height: 4),
          Text(title, maxLines: 2,
              style: const TextStyle(
                color: _white, fontSize: 19,
                fontWeight: FontWeight.w900, letterSpacing: -.25)),
          const SizedBox(height: 3),
          Text(description, maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      )),
      if (action != null)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: TextButton(
            onPressed: onTap,
            child: Text(action),
          ),
        ),
    ]);

  Widget _metric(double width, String label, String value, String caption,
      IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: width,
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _mint.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: _mint, size: 19),
                  ),
                  const Spacer(),
                  const Icon(Icons.north_east_rounded,
                      size: 16, color: _muted),
                ]),
                const SizedBox(height: 14),
                Text(value,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _white, fontSize: 25,
                      fontWeight: FontWeight.w900, letterSpacing: -.55,
                    )),
                const SizedBox(height: 5),
                Text(label,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _white, fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 3),
                Text(caption, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, String title, VoidCallback onTap) =>
    Material(
      color: _card2,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _stroke),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: _mint, size: 18),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 169),
              child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _white, fontSize: 12, fontWeight: FontWeight.w700))),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: _muted, size: 15),
          ]),
        ),
      ),
    );

  Widget _priorityCard({
    required String title,
    required IconData icon,
    required int count,
    required VoidCallback onAll,
    required List<Widget> children,
  }) =>
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: _surfaceDecoration(),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 15, 12, 6),
          child: Row(children: [
            Icon(icon, color: _mint, size: 20),
            const SizedBox(width: 9),
            Expanded(child: Text(title,
                style: const TextStyle(
                  color: _white, fontSize: 14, fontWeight: FontWeight.w900))),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _mint.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count',
                  style: const TextStyle(color: _mint,
                      fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const SizedBox(width: 3),
            IconButton(
              tooltip: 'Tümünü gör',
              onPressed: onAll,
              icon: const Icon(Icons.arrow_forward_rounded,
                  color: _muted, size: 19),
            ),
          ]),
        ),
        ...children,
      ]),
    );

  Widget _rowTile({
    required String name,
    required String info,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
    Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 15, vertical: 13),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF24372B),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: _mint, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _white, fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(info, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10)),
              ],
            )),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: _muted, size: 20),
          ]),
        ),
      ),
    );

  Widget _quickCommand({
    required String title, required String detail,
    required IconData icon, required VoidCallback onTap,
  }) => Material(
    color: _card,
    borderRadius: BorderRadius.circular(17),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _stroke),
        ),
        child: Row(children: [
          Container(width: 45, height: 45,
            decoration: BoxDecoration(
              color: _mint.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: _mint, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _white, fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 10)),
            ],
          )),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios_rounded,
              color: _muted, size: 14),
        ]),
      ),
    ),
  );

  Widget _emptyMini(String message) =>
    Container(
      width: double.infinity,
      decoration: _surfaceDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 19),
      child: Row(children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: _mint, size: 19),
        const SizedBox(width: 10),
        Expanded(child: Text(message,
            style: const TextStyle(color: _muted, fontSize: 12))),
      ]),
    );
}
