import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'core/constants/app_constants.dart';
import 'services/authenticated_http_client.dart';
import 'rewards_store_screen.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({
    super.key,
    required this.userId,
    required this.userType,
  });

  final int userId;
  final String userType;

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  late final AuthenticatedHttpClient _client =
      AuthenticatedHttpClient(http.Client());

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uri = Uri.parse(AppConstants.baseUrl).replace(queryParameters: {
        'action': 'get_referral_summary',
        'user_id': widget.userId.toString(),
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> ||
          response.statusCode != 200 ||
          decoded['status'] != 'success') {
        throw Exception(decoded is Map
            ? decoded['message']?.toString() ?? 'Davet bilgileri alınamadı.'
            : 'Davet bilgileri alınamadı.');
      }
      if (!mounted) return;
      setState(() => _data = decoded);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyCode() async {
    final code = _data?['referral_code']?.toString() ?? '';
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Davet kodu kopyalandı.')));
  }

  Future<void> _copyInviteText() async {
    final code = _data?['referral_code']?.toString() ?? '';
    if (code.isEmpty) return;
    final invited = _data?['invited_reward'] ?? 50;
    final text =
        'OTO TAG\'a katıl. Kayıtta davet kodumu kullan: $code. İlk gerçek işlemini tamamladığında $invited OTO TAG Puan kazanırsın.';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Davet mesajı kopyalandı.')));
  }

  int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final stats = data?['stats'] is Map
        ? Map<String, dynamic>.from(data!['stats'] as Map)
        : <String, dynamic>{};
    final referrals = data?['referrals'] is List
        ? (data!['referrals'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        title: const Text('Arkadaşını Davet Et'),
        backgroundColor: AppConstants.bgColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
              tooltip: 'Yenile',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _panel(
                child: Column(children: [
                  const Icon(Icons.cloud_off_rounded, size: 34),
                  const SizedBox(height: 10),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tekrar dene'),
                  )
                ]),
              ),
            ],
            if (data != null) ...[
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Arkadaşını getir, birlikte kazan',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(
                      'Arkadaşın ilk gerçek OTO TAG işlemini tamamladığında sen ${_int(data['inviter_reward'])} puan, arkadaşın ${_int(data['invited_reward'])} puan kazanır.',
                      style: const TextStyle(
                          color: Colors.white70, height: 1.5, fontSize: 13),
                    ),
                    const SizedBox(height: 22),
                    const Text('DAVET KODUN',
                        style: TextStyle(
                            color: AppConstants.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.3)),
                    const SizedBox(height: 8),
                    SelectableText(
                      data['referral_code']?.toString() ?? '-',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _copyCode,
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Kodu Kopyala'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _copyInviteText,
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Davet Mesajını Kopyala'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RewardsStoreScreen(userId: widget.userId),
                            ),
                          ).then((_) => _load()),
                          icon: const Icon(Icons.stars_rounded),
                          label: const Text('Puan Mağazası'),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _statCard('Puanın', _int(data['reward_points']),
                        Icons.stars_rounded)),
                const SizedBox(width: 10),
                Expanded(
                    child: _statCard('Davet', _int(stats['total']),
                        Icons.group_add_rounded)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _statCard('Tamamlanan', _int(stats['rewarded']),
                        Icons.verified_rounded)),
                const SizedBox(width: 10),
                Expanded(
                    child: _statCard('Bekleyen', _int(stats['pending']),
                        Icons.schedule_rounded)),
              ]),
              const SizedBox(height: 22),
              const Text('Davetlerin',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (referrals.isEmpty)
                _panel(
                    child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Henüz davetin yok. Kodunu arkadaşlarınla paylaşarak başlayabilirsin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.45),
                  ),
                ))
              else
                for (final item in referrals) _referralTile(item),
              const SizedBox(height: 14),
              const Text(
                'Ödül, davet edilen hesap ilk gerçek ve tamamlanmış servis veya kiralama işlemine ulaştığında bir kez verilir. İptal edilen veya tahmini eşleşmeler ödül oluşturmaz.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white54, fontSize: 11, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: child,
      );

  Widget _statCard(String label, int value, IconData icon) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppConstants.primaryColor, size: 21),
          const SizedBox(height: 14),
          Text('$value',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      );

  Widget _referralTile(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'pending';
    final rewarded = status == 'rewarded';
    final rejected = status == 'rejected';
    final label = rewarded
        ? 'Ödül kazanıldı'
        : rejected
            ? 'Ödül uygun değil'
            : 'İlk işlem bekleniyor';
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        tileColor: AppConstants.cardColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: .06))),
        leading: CircleAvatar(
          backgroundColor: AppConstants.primaryColor.withValues(alpha: .12),
          child: Icon(
              rewarded
                  ? Icons.check_rounded
                  : rejected
                      ? Icons.close_rounded
                      : Icons.hourglass_top_rounded,
              color: AppConstants.primaryColor),
        ),
        title: Text(item['invited_name']?.toString() ?? 'OTO TAG kullanıcısı',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        trailing: rewarded
            ? Text('+${_int(item['inviter_points'])}',
                style: const TextStyle(
                    color: AppConstants.primaryColor,
                    fontWeight: FontWeight.w900))
            : null,
      ),
    );
  }
}
