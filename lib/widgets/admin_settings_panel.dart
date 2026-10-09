import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Management tools and recent authenticated API activity, in one responsive view.
/// "Etkin" means an authenticated request within the indicated time window.
/// It is not a socket/presence connection.
class AdminSettingsPanel extends StatefulWidget {
  const AdminSettingsPanel({
    super.key,
    required this.users,
    required this.loaded,
    required this.loading,
    required this.updatedAt,
    required this.error,
    required this.onRefresh,
    required this.onOpenUser,
    required this.onMembers,
    required this.onUpdates,
    required this.onRental,
    required this.onAds,
    required this.onPurchases,
    required this.onFeedback,
    required this.onTelemetry,
    required this.onGrowth,
    required this.onPassword,
    required this.onBackup,
    required this.onOptimize,
    required this.onLogout,
  });

  final List<Map<String, dynamic>> users;
  final bool loaded, loading;
  final DateTime? updatedAt;
  final String? error;
  final VoidCallback onRefresh, onMembers, onUpdates, onRental, onAds,
      onPurchases, onFeedback, onTelemetry, onGrowth, onPassword,
      onBackup, onOptimize, onLogout;
  final ValueChanged<Map<String, dynamic>> onOpenUser;

  @override
  State<AdminSettingsPanel> createState() => _AdminSettingsPanelState();
}

/// Use relative seconds calculated in SQL to avoid device/server timezone drift.
/// Older API deployments only return a wall-clock last_seen_at timestamp.
int? adminLastActivitySeconds(Map<String, dynamic> user, {
  required DateTime now,
  DateTime? fetchedAt,
}) {
  final seconds = int.tryParse('${user['last_seen_seconds_ago'] ?? ''}');
  if (seconds != null) {
    final passed = fetchedAt == null ? 0
        : now.difference(fetchedAt).inSeconds;
    return seconds + (passed > 0 ? passed : 0);
  }
  final stamp = user['last_seen_at']?.toString();
  if (stamp == null || stamp.trim().isEmpty) return null;
  final seen = DateTime.tryParse(stamp.replaceFirst(' ', 'T'));
  if (seen == null) return null;
  return now.difference(seen).inSeconds;
}

class _AdminSettingsPanelState extends State<AdminSettingsPanel> {
  static const bg = Color(0xFF0B120F);
  static const surface = Color(0xFF14231B);
  static const line = Color(0xFF2B4335);
  static const green = Color(0xFF00DE91);
  static const white = Color(0xFFF2FAF4);
  static const muted = Color(0xFFA2B7A9);
  static const amber = Color(0xFFF4C576);
  String _window = 'recent';
  String _role = 'all';
  String _search = '';

  bool _isEligible(Map<String, dynamic> user) {
    final suspended = '${user['is_suspended'] ?? ''}';
    return user['status'] == 'active' &&
        suspended != '1' && suspended != 'true';
  }

  String _roleLabel(dynamic kind) => switch (kind) {
    'customer' => 'Müşteri',
    'provider' => 'Usta',
    'rentacar' => 'Kiralama firması',
    _ => 'Üye',
  };

  IconData _roleIcon(dynamic kind) => switch (kind) {
    'provider' => Icons.handyman_rounded,
    'rentacar' => Icons.directions_car_rounded,
    _ => Icons.person_outline_rounded,
  };

  String _lastSeen(Map<String, dynamic> user, DateTime now) {
    final age = adminLastActivitySeconds(user, now: now,
        fetchedAt: widget.updatedAt);
    if (age == null) return 'Henüz hareket kaydı yok';
    if (age >= 0 && age < 60) return 'Az önce etkin';
    if (age >= 0 && age < 3600) return '${age ~/ 60} dk önce etkin';
    if (age >= 0 && age < 86400) return '${age ~/ 3600} saat önce etkin';
    final stamp = user['last_seen_at']?.toString() ?? '';
    final parsed = DateTime.tryParse(stamp.replaceFirst(' ', 'T'));
    return parsed == null ? 'Son görülme bilinmiyor'
        : DateFormat('dd.MM.yyyy HH:mm').format(parsed);
  }

  Widget _header(String eyebrow, String heading, String description) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(eyebrow, style: const TextStyle(color: green,
            fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
        const SizedBox(height: 5),
        Text(heading, style: const TextStyle(color: white, fontSize: 19,
            fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(color: muted,
            fontSize: 12, height: 1.4)),
      ]);

  Widget _stat(String label, String value, IconData icon, Color accent,
      double width, String hint) => SizedBox(
    width: width,
    child: Container(
      constraints: const BoxConstraints(minHeight: 122),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surface,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(17)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: accent, size: 21),
          const Spacer(),
          Icon(Icons.circle, color: accent, size: 7),
        ]),
        const SizedBox(height: 11),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: white, fontSize: 26,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: white, fontSize: 12,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(hint, maxLines: 2, style: const TextStyle(
            color: muted, fontSize: 10)),
      ]),
    ),
  );

  Widget _tool(IconData icon, String label, String subtitle,
      VoidCallback onTap, {bool critical = false}) {
    final accent = critical ? const Color(0xFFFF8987) : green;
    return Material(
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: Row(children: [
            Container(width: 43, height: 43,
                decoration: BoxDecoration(color: accent.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: accent, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: white, fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11)),
              ])),
            const SizedBox(width: 7),
            Icon(Icons.chevron_right_rounded, color: accent, size: 21),
          ]),
        ),
      ),
    );
  }

  Widget _toolGrid(List<Widget> tiles) => LayoutBuilder(
    builder: (context, limits) {
      final wide = limits.maxWidth >= 670;
      return Wrap(spacing: 11, runSpacing: 11, children: [
        for (final tile in tiles)
          SizedBox(width: wide ? (limits.maxWidth - 11) / 2
              : limits.maxWidth, child: tile),
      ]);
    },
  );

  Widget _pill(String text, String value, String selected,
      ValueChanged<String> change) {
    final current = selected == value;
    return ChoiceChip(
      label: Text(text, style: TextStyle(
          color: current ? bg : white,
          fontSize: 11, fontWeight: FontWeight.w800)),
      selected: current,
      onSelected: (_) => change(value),
      selectedColor: green,
      backgroundColor: surface,
      side: BorderSide(color: current ? green : line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = widget.users.where((u) {
      final age = adminLastActivitySeconds(u,
          now: now, fetchedAt: widget.updatedAt);
      return _isEligible(u) && age != null && age >= 0 && age <= 300;
    }).toList();
    final day = widget.users.where((u) {
      final age = adminLastActivitySeconds(u,
          now: now, fetchedAt: widget.updatedAt);
      return age != null && age >= 0 && age <= 86400;
    }).toList();
    final workers = active.where((u) => u['user_type'] == 'provider').length;
    final customers = active.where((u) => u['user_type'] == 'customer').length;
    final companies = active.where((u) => u['user_type'] == 'rentacar').length;
    final source = _window == 'recent' ? active
        : _window == 'day' ? day : widget.users;
    final result = source.where((u) {
      if (_role != 'all' && u['user_type'] != _role) return false;
      final search = _search.trim().toLowerCase();
      if (search.isEmpty) return true;
      return ['name', 'phone', 'email', 'city', 'id'].any(
        (key) => (u[key]?.toString() ?? '').toLowerCase().contains(search));
    }).toList()
      ..sort((a, b) {
        final left = adminLastActivitySeconds(a, now: now,
            fetchedAt: widget.updatedAt) ?? 999999999;
        final right = adminLastActivitySeconds(b, now: now,
            fetchedAt: widget.updatedAt) ?? 999999999;
        return left.compareTo(right);
      });

    return ColoredBox(color: bg,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(13, 14, 13, 36),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  Color(0xFF173D2A), Color(0xFF0D1B15)
                ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                border: Border.all(color: const Color(0xFF2B7651)),
                borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.tune_rounded, color: green, size: 18),
                  SizedBox(width: 8),
                  Text('OTO TAG  /  KONTROL MERKEZİ',
                    style: TextStyle(color: green, fontSize: 10,
                        fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                ]),
                const SizedBox(height: 14),
                const Text('Yönetim ayarları', style: TextStyle(
                    color: white, fontSize: 25, fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                const Text('Üyelerin son etkinliğini takip edin, işlemlere hızlı erişin ve sistemi yönetin.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
                const SizedBox(height: 16),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  FilledButton.icon(
                    onPressed: widget.loading ? null : widget.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(widget.loading ? 'Yükleniyor' : 'Etkinliği yenile'),
                    style: FilledButton.styleFrom(backgroundColor: green,
                        foregroundColor: bg)),
                  OutlinedButton.icon(
                    onPressed: widget.onMembers,
                    icon: const Icon(Icons.groups_rounded, size: 17),
                    label: const Text('Üyeleri yönet'),
                    style: OutlinedButton.styleFrom(foregroundColor: white,
                        side: const BorderSide(color: line)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 25),
            _header('01 / ETKİNLİK', 'Kullanıcı hareketleri',
                'Son 5 dakikadaki doğrulanmış API hareketlerine göre tahmini etkinlik.'),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, bounds) {
              final columns = bounds.maxWidth >= 970 ? 4 : 2;
              final width = (bounds.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                _stat('Son 5 dk etkin', widget.loaded ? '${active.length}' : '—',
                    Icons.podcasts_rounded, green, width, 'Yaklaşık etkinlik'),
                _stat('Aktif müşteriler', widget.loaded ? '$customers' : '—',
                    Icons.person_rounded, const Color(0xFF75CFFF), width,
                    'Son 5 dakikada'),
                _stat('Aktif ustalar', widget.loaded ? '$workers' : '—',
                    Icons.handyman_rounded, amber, width, 'Son 5 dakikada'),
                _stat('Aktif firmalar', widget.loaded ? '$companies' : '—',
                    Icons.business_center_rounded, const Color(0xFFD5B0FF),
                    width, 'Son 5 dakikada'),
              ]);
            }),
            const SizedBox(height: 11),
            const Row(children: [
              Icon(Icons.info_outline_rounded, size: 17, color: muted),
              const SizedBox(width: 7),
              const Expanded(child: Text('Çevrimiçi bağlantı sayısı değil; son API hareketi esas alınır. Boşta açık uygulamalar görünmeyebilir.',
                  style: TextStyle(color: muted, fontSize: 11))),
            ]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: surface,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(17)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.radar_rounded, color: green, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Son etkinlik listesi',
                    style: TextStyle(color: white, fontSize: 16,
                        fontWeight: FontWeight.w900))),
                  if (widget.loading)
                    const SizedBox(width: 17, height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
                const SizedBox(height: 7),
                Text(widget.loaded
                    ? '${widget.users.length} kayıt yüklendi · Son 24 saatte ${day.length} kullanıcı etkin'
                    : 'Etkinlik kayıtları yükleniyor',
                    style: const TextStyle(color: muted, fontSize: 11)),
                if (widget.updatedAt != null)
                  Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text('Son yenileme: ${DateFormat('HH:mm:ss').format(widget.updatedAt!)}',
                      style: const TextStyle(color: muted, fontSize: 10))),
                if (widget.users.length >= 1500)
                  const Padding(padding: EdgeInsets.only(top: 7),
                    child: Text('Yalnızca en yeni 1500 hesap gösteriliyor. Toplam çevrimiçi sayısı değildir.',
                      style: TextStyle(color: amber, fontSize: 11))),
                if (widget.error != null)
                  Padding(padding: const EdgeInsets.only(top: 9),
                    child: Text(widget.error!, style: const TextStyle(
                      color: Color(0xFFFF9494), fontSize: 12))),
                const SizedBox(height: 14),
                Wrap(spacing: 6, runSpacing: 5, children: [
                  _pill('Son 5 dk', 'recent', _window,
                      (v) => setState(() => _window = v)),
                  _pill('Son 24 saat', 'day', _window,
                      (v) => setState(() => _window = v)),
                  _pill('Tüm üyeler', 'all', _window,
                      (v) => setState(() => _window = v)),
                ]),
                const SizedBox(height: 9),
                TextField(
                  onChanged: (value) => setState(() => _search = value),
                  style: const TextStyle(color: white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'İsim, telefon, e-posta veya üye ID ara',
                    hintStyle: const TextStyle(color: muted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, color: muted),
                    isDense: true, filled: true, fillColor: bg,
                    border: OutlineInputBorder(
                      borderSide: const BorderSide(color: line),
                      borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: line),
                      borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 5, runSpacing: 3, children: [
                  _pill('Tüm roller', 'all', _role,
                      (v) => setState(() => _role = v)),
                  _pill('Müşteri', 'customer', _role,
                      (v) => setState(() => _role = v)),
                  _pill('Usta', 'provider', _role,
                      (v) => setState(() => _role = v)),
                  _pill('Firma', 'rentacar', _role,
                      (v) => setState(() => _role = v)),
                ]),
                const SizedBox(height: 12),
                if (!widget.loaded && widget.loading)
                  const Padding(padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()))
                else if (!widget.loaded)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Veriler henüz alınamadı. Etkinliği yenile düğmesine basın.',
                        style: TextStyle(color: muted)))
                else if (result.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Bu filtrede etkin kullanıcı bulunamadı.',
                        style: TextStyle(color: muted)))
                else ...[
                  for (final user in result.take(12))
                    Material(color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onOpenUser(user),
                        borderRadius: BorderRadius.circular(11),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10,
                              horizontal: 3),
                          child: Row(children: [
                            Stack(clipBehavior: Clip.none, children: [
                              Container(width: 39, height: 39,
                                  decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(color: line)),
                                  child: Icon(_roleIcon(user['user_type']),
                                      color: green, size: 20)),
                              if (active.any((u) => u['id'] == user['id']))
                                const Positioned(right: -3, bottom: -3,
                                    child: CircleAvatar(radius: 6,
                                        backgroundColor: green)),
                            ]),
                            const SizedBox(width: 11),
                            Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user['name']?.toString() ?? 'İsimsiz üye',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: white,
                                        fontSize: 13, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text('${_roleLabel(user['user_type'])} · ${_lastSeen(user, now)}',
                                    maxLines: 2,
                                    style: const TextStyle(color: muted,
                                        fontSize: 11)),
                                ])),
                            const Icon(Icons.chevron_right_rounded,
                                color: green, size: 19),
                          ]),
                        ),
                      ),
                    ),
                  if (result.length > 12)
                    Text('${result.length - 12} ek kayıt var. Üyeler bölümünde tümünü inceleyin.',
                        style: const TextStyle(color: muted, fontSize: 11)),
                ],
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: widget.onMembers,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                      label: const Text('Tüm üyeleri aç'))),
              ]),
            ),
            const SizedBox(height: 27),
            _header('02 / İŞLEMLER', 'İçerik ve işletme',
                'Yayındaki içerikler, gelir ve müşteri geri bildirimleri.'),
            const SizedBox(height: 12),
            _toolGrid([
              _tool(Icons.campaign_outlined, 'Reklam yönetimi',
                  'Banner ve kampanyaları yönet', widget.onAds),
              _tool(Icons.workspace_premium_outlined, 'Abonelik ve satın alımlar',
                  'Premium ve ödeme kayıtları', widget.onPurchases),
              _tool(Icons.feedback_outlined, 'Geri bildirimler',
                  'Kullanıcı görüşlerini incele', widget.onFeedback),
              _tool(Icons.insights_outlined, 'Kullanım analizi',
                  'Hata, bekleme ve tıklama verileri', widget.onTelemetry),
              _tool(Icons.trending_up_rounded, 'Büyüme analizi',
                  'Kayıt, dönüşüm ve şehir raporları', widget.onGrowth),
              _tool(Icons.car_rental_rounded, 'Kiralama takip',
                  'Firma ve rezervasyon işlemleri', widget.onRental),
            ]),
            const SizedBox(height: 27),
            _header('03 / SİSTEM', 'Güvenlik ve bakım',
                'Sürüm yayınlama, erişim güvenliği ve sistem araçları.'),
            const SizedBox(height: 12),
            _toolGrid([
              _tool(Icons.system_update_rounded, 'Android / iPhone sürümleri',
                  'Duyurular ve güncelleme yönetimi', widget.onUpdates),
              _tool(Icons.lock_reset_rounded, 'Admin şifresi değiştir',
                  'Hesap güvenliğini güncelle', widget.onPassword),
              _tool(Icons.backup_rounded, 'Veritabanı yedeği',
                  'Manuel yedek oluştur', widget.onBackup),
              _tool(Icons.cleaning_services_rounded, 'Sistem optimizasyonu',
                  'Bakım ve temizlik işlemleri', widget.onOptimize),
              _tool(Icons.logout_rounded, 'Güvenli çıkış',
                  'Yönetici oturumunu sonlandır', widget.onLogout,
                  critical: true),
            ]),
          ]),
        )),
      ),
    );
  }
}
