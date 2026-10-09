import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_command_palette.dart';
import '../core/constants/app_constants.dart';

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

  @override
  Widget build(BuildContext context) {
    final open = tickets.where((t) => t['status'] == 'open').toList();
    final theme = Theme.of(context);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hero(context, pendingCount: pending.length,
                openCount: open.length),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 520
                      ? 2
                      : 1;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                _metric(
                    context,
                    width,
                    'Servis cirosu',
                    dashboardReady
                        ? NumberFormat.currency(locale: 'tr_TR', symbol: '₺')
                            .format(revenue)
                        : '—',
                    'Son 30 gün · tamamlanan işler',
                    Icons.account_balance_wallet_outlined,
                    () => onCommand('section:3')),
                _metric(
                    context,
                    width,
                    'Tamamlanan servis',
                    dashboardReady ? '$completedJobs' : '—',
                    'Son 30 gün',
                    Icons.task_alt,
                    () => onCommand('section:3')),
                _metric(
                    context,
                    width,
                    'Müşteriler',
                    dashboardReady ? '$customers' : '—',
                    'Kayıtlı müşteri hesapları',
                    Icons.person_outline,
                    () => onCommand('customers')),
                _metric(
                    context,
                    width,
                    'Ustalar',
                    dashboardReady ? '$providers' : '—',
                    'Kayıtlı usta hesapları',
                    Icons.build_outlined,
                    () => onCommand('providers')),
                _metric(
                    context,
                    width,
                    'Firmalar',
                    dashboardReady ? '$companies' : '—',
                    'Kiralama firması hesapları',
                    Icons.business_outlined,
                    () => onCommand('companies')),
                _metric(
                    context,
                    width,
                    'Açık destek',
                    ticketsReady ? '${open.length}' : '—',
                    'Yüklenen talepler arasında',
                    Icons.support_agent_outlined,
                    () => onCommand('section:4')),
              ]);
            }),
            const SizedBox(height: 24),
            _heading(context, 'Öncelikli işler'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  avatar: const Icon(Icons.how_to_reg_outlined, size: 18),
                  label: Text(dashboardReady
                      ? '${pending.length} başvuru bekliyor'
                      : 'Başvurular alınamadı'),
                  onPressed: () => onCommand('section:1')),
              ActionChip(
                  avatar: const Icon(Icons.support_agent_outlined, size: 18),
                  label: Text(ticketsReady
                      ? '${open.length} açık destek talebi'
                      : 'Destek verisi alınamadı'),
                  onPressed: () => onCommand('section:4')),
              ActionChip(
                  avatar: const Icon(Icons.business_outlined, size: 18),
                  label: Text(dashboardReady
                      ? '$companies kiralama firması'
                      : 'Firma verisi alınamadı'),
                  onPressed: () => onCommand('companies')),
            ]),
            const SizedBox(height: 12),
            if (pending.isNotEmpty)
              _surface(
                  context,
                  Column(children: [
                    for (final person in pending.take(3))
                      ListTile(
                          leading: const Icon(Icons.pending_actions_outlined),
                          title: Text('${person['name'] ?? 'Başvuru'}'),
                          subtitle: Text(person['user_type'] == 'rentacar'
                              ? 'Kiralama firması · belgeleri incele'
                              : '${serviceLabel(person['service_category']?.toString())} · belgeleri incele'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onCommand('section:1')),
                  ])),
            if (open.isNotEmpty) ...[
              const SizedBox(height: 12),
              _surface(
                  context,
                  Column(children: [
                    for (final ticket in open.take(3))
                      ListTile(
                          leading: const Icon(Icons.mark_email_unread_outlined),
                          title: Text('${ticket['subject'] ?? 'Destek talebi'}',
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Talep #${ticket['id']}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onTicket(ticket)),
                  ])),
            ],
            if (dashboardReady &&
                ticketsReady &&
                pending.isEmpty &&
                open.isEmpty)
              _surface(
                  context,
                  const ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text(
                          'Bekleyen başvuru veya açık destek talebi bulunmuyor.'))),
            const SizedBox(height: 24),
            _heading(context, 'Hızlı erişim'),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960
                  ? 3
                  : constraints.maxWidth >= 580
                      ? 2
                      : 1;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final command in commands)
                  SizedBox(
                      width: width,
                      child: _surface(
                          context,
                          ListTile(
                              leading: Icon(command.icon,
                                  color: theme.colorScheme.primary),
                              title: Text(command.title),
                              subtitle: Text(command.subtitle),
                              trailing:
                                  const Icon(Icons.chevron_right, size: 18),
                              onTap: () => onCommand(command.id)))),
              ]);
            }),
            const SizedBox(height: 24),
            _heading(context, 'Son servis talepleri',
                action: 'Tümünü gör', onTap: () => onCommand('section:3')),
            Text('Sunucunun getirdiği son 100 kayıt içinden en yeni 5 talep.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            _surface(
                context,
                jobs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(dashboardReady
                            ? 'Henüz servis talebi bulunmuyor.'
                            : 'Servis verisi alınamadı.'))
                    : Column(children: [
                        for (final job in jobs.take(5))
                          ListTile(
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: Text(
                                  '#${job['id']} · ${serviceLabel(job['service_type']?.toString())}'),
                              subtitle: Text(
                                  '${job['customer_name'] ?? 'Müşteri'} · ${statusLabel(job['status']?.toString())}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => onJob(job)),
                      ])),
            footer,
          ]),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context,
      {required int pendingCount, required int openCount}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1510),
            Color(0xFF152B20),
            Color(0xFF0A1510),
          ],
        ),
        border: Border.all(
            color: AppConstants.primaryColor.withValues(alpha: .22)),
      ),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(builder: (context, bounds) {
        final wide = bounds.maxWidth >= 680;
        final introduction = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.admin_panel_settings_rounded,
                  color: AppConstants.primaryColor, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('OTO TAG / KONTROL MERKEZİ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppConstants.primaryColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      fontSize: 10,
                    )),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Yönetim merkezi',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                  fontSize: 25,
                )),
            const SizedBox(height: 6),
            const Text(
              'Her şey kontrolünüzde. Üyeleri, başvuruları ve işlemleri yönetin.',
              style: TextStyle(color: Color(0xFFB9CAC0), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 9, runSpacing: 8, children: [
              _heroAction(
                icon: Icons.verified_user_outlined,
                label: 'Başvurular',
                count: dashboardReady ? '$pendingCount' : '—',
                onTap: () => onCommand('section:1'),
              ),
              _heroAction(
                icon: Icons.support_agent_outlined,
                label: 'Açık destek',
                count: ticketsReady ? '$openCount' : '—',
                onTap: () => onCommand('section:4'),
              ),
            ]),
          ],
        );
        if (!wide) return introduction;
        return Row(children: [
          Expanded(child: introduction),
          const SizedBox(width: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => onCommand('section:2'),
                  icon: const Icon(Icons.groups_rounded),
                  label: const Text('Üyeleri yönet'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => onCommand('analytics'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.insights_rounded),
                  label: const Text('Analizler'),
                ),
              ],
            ),
          ),
        ]);
      }),
    );
  }

  Widget _heroAction({
    required IconData icon,
    required String label,
    required String count,
    required VoidCallback onTap,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Material(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, color: AppConstants.primaryColor, size: 17),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
              ),
              const SizedBox(width: 7),
              Text(count,
                  style: const TextStyle(
                      color: AppConstants.primaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _surface(BuildContext context, Widget child) => Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .5))),
      clipBehavior: Clip.antiAlias,
      child: child);

  Widget _heading(BuildContext context, String title,
          {String? action, VoidCallback? onTap}) =>
      Row(children: [
        Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700))),
        if (action != null) TextButton(onPressed: onTap, child: Text(action)),
      ]);

  Widget _metric(BuildContext context, double width, String label,
      String value, String description, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .65),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: AppConstants.primaryColor.withValues(alpha: .12),
                    ),
                    child: Icon(icon,
                        color: AppConstants.primaryDark, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.arrow_outward_rounded,
                      size: 15,
                      color: scheme.onSurface.withValues(alpha: .45)),
                ]),
                const SizedBox(height: 14),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4),
                ),
                const SizedBox(height: 6),
                Text(description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
