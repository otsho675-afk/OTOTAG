import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/constants/app_constants.dart';
import 'services/rental_service.dart';
import 'services/subscription_store.dart';
import 'widgets/rental_market_style.dart';

class BusinessSubscriptionScreen extends StatefulWidget {
  const BusinessSubscriptionScreen(
      {super.key,
      required this.userId,
      this.userType = 'rentacar',
      this.business = true,
      this.premium = false,
      this.service,
      this.store});
  final int userId;
  final String userType;
  final bool business;
  final bool premium;
  final RentalService? service;
  final SubscriptionStore? store;
  @override
  State<BusinessSubscriptionScreen> createState() =>
      _BusinessSubscriptionScreenState();
}

class _BusinessSubscriptionScreenState
    extends State<BusinessSubscriptionScreen> {
  late final _service = widget.service ?? RentalService();
  late final _store = widget.store ?? MobileSubscriptionStore();
  StreamSubscription<List<PurchaseDetails>>? _listener;
  ProductDetails? _product;
  Map<String, dynamic>? _status;
  bool _loading = true, _busy = false;
  String? _error, _notice;
  Future<void> _queue = Future.value();
  final Set<String> _processed = {};
  bool get _business => widget.business && !widget.premium;
  String get _productId => widget.premium
      ? (_store.platform == 'apple'
          ? 'ototag_premium_monthly'
          : 'customer_premium_monthly')
      : !_business
          ? 'diagnostic_monthly_100tl'
          : _store.platform == 'apple'
              ? 'ototag_provider_monthly'
              : 'provider_monthly_subscription';
  bool get _active =>
      _status?[_business ? 'can_work' : 'is_subscribed'] == true;
  @override
  void initState() {
    super.initState();
    _listener = _store.purchases.listen((purchases) {
      _queue = _queue.then((_) => _purchases(purchases)).catchError((Object _) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error =
                'Ödeme işlemi tamamlanamadı. Satın alımları geri yükleyin.';
          });
        }
      });
    }, onError: (Object _) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Mağaza bağlantısı kesildi. Tekrar deneyin.';
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _listener?.cancel();
    if (widget.service == null) _service.dispose();
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
      final status = widget.premium
          ? await _service.premiumSubscription(widget.userId)
          : _business
              ? await _service.businessSubscription(widget.userId)
              : await _service.diagnosticSubscription(widget.userId);
      if (mounted) setState(() => _status = status);
      final product = await _store.product(_productId);
      if (mounted) {
        setState(() {
          _product = product;
          if (_store.supported && product == null) {
            _error =
                'Abonelik mağazada bulunamadı. Mağaza hesabınızı kontrol edip tekrar deneyin.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _product = null;
          _error = 'Abonelik veya mağaza bilgisi alınamadı. Tekrar deneyin.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _purchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != _productId) continue;
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() {
            _busy = true;
            _notice = 'Ödeme mağazada bekleniyor…';
          });
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        if (mounted) {
          setState(() {
            _busy = false;
            _notice = null;
            _error =
                'Ödeme iptal edildi veya tamamlanamadı. Tekrar deneyebilirsiniz.';
          });
        }
        continue;
      }
      final key =
          '${purchase.productID}:${purchase.purchaseID}:${purchase.verificationData.serverVerificationData}';
      if (_processed.contains(key)) continue;
      try {
        if (mounted) {
          setState(() {
            _busy = true;
            _error = null;
            _notice = 'Ödeme sunucuda doğrulanıyor…';
          });
        }
        await _service.verifySubscription(
            userId: widget.userId,
            userType: widget.userType,
            productId: purchase.productID,
            platform: _store.platform,
            receipt: purchase.verificationData.serverVerificationData,
            orderId: purchase.purchaseID ?? '',
            business: _business,
            premium: widget.premium);
        // Never acknowledge or unlock an unverified receipt.
        if (purchase.pendingCompletePurchase) await _store.complete(purchase);
        _processed.add(key);
        await _load();
        if (mounted) {
          setState(() => _notice = _active
              ? 'Aboneliğiniz doğrulandı ve aktif.'
              : 'Ödeme doğrulandı. Abonelik durumunu yenileyin.');
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _notice = null;
            _error =
                '$e\nBağlantınızı kontrol edip satın alımları geri yükleyin.';
          });
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _buy() async {
    if (_busy ||
        _product == null ||
        _status == null ||
        _active && _status?['is_trial'] != true) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = 'Mağaza ödeme ekranı açılıyor…';
    });
    try {
      if (!await _store.buy(_product!)) {
        throw StateError('Ödeme ekranı açılamadı.');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = null;
          _error =
              'Mağaza ödeme ekranı açılamadı. Zaten aboneyseniz satın alımları geri yükleyin.';
        });
      }
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = 'Satın alımlar kontrol ediliyor…';
    });
    try {
      await _store.restore();
      await _queue;
      await _load();
      if (mounted) {
        setState(() => _notice =
            'Mağazanın gönderdiği makbuzlar doğrulanır. Aboneliğiniz görünmüyorsa aynı mağaza hesabını kullandığınızı kontrol edin.');
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Satın alımlar geri yüklenemedi. Tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link(String url) async {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
    }
  }

  String get _title => widget.premium
      ? 'Premium Garaj'
      : _business
          ? (widget.userType == 'provider'
              ? 'Usta üyeliği'
              : 'Rent A Car üyeliği')
          : 'Arıza tespit üyeliği';
  List<String> get _features => widget.premium
      ? [
          'Garajına birden fazla araç ekle',
          'Araçlarının bakım ve kilometre kayıtlarını tek yerde takip et',
          'Araç bazında hatırlatıcılarını yönet'
        ]
      : _business
          ? widget.userType == 'provider'
              ? [
                  'Hizmetine uygun yakın talepleri gör',
                  'Teklif ver, müşterinle anlaş ve işlerini yönet',
                  'Kazanç ve işlem geçmişine ulaş'
                ]
              : [
                  'Aynı şehirde bütçeye uygun müşteri eşleşmesi',
                  'Araç, teklif ve rezervasyon yönetimi',
                  'Canlı OBD arıza tespiti üyeliğe dahil'
                ]
          : [
              'Uyumlu ELM327 Wi-Fi adaptörü ile araç bağlantısı',
              'Gerçek arıza kodları ve desteklenen sensör verileri',
              'Satın alımlarını mağaza hesabınla geri yükle'
            ];
  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: Scaffold(
          appBar: AppBar(title: Text(_title)),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                              color: AppConstants.primaryColor
                                                  .withValues(alpha: .1),
                                              borderRadius:
                                                  BorderRadius.circular(18)),
                                          child: const Icon(
                                              Icons.workspace_premium_outlined,
                                              color: AppConstants.primaryColor,
                                              size: 28)),
                                      const SizedBox(width: 14),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(
                                                widget.premium
                                                    ? 'Garajını genişlet'
                                                    : _business
                                                        ? 'İşine odaklan'
                                                        : 'Aracını daha iyi tanı',
                                                style: const TextStyle(
                                                    fontSize: 24,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            const SizedBox(height: 6),
                                            Text(
                                                widget.premium
                                                    ? 'Araçların ve bakım kayıtların tek yerde.'
                                                    : _business
                                                        ? 'İlk 30 gün ücretsiz. Sonrasında aylık üyelik.'
                                                        : 'İlk 10 bağlantı ücretsiz. Sonrasında aylık üyelik.',
                                                style: const TextStyle(
                                                    color: rentalMuted,
                                                    height: 1.5)),
                                          ])),
                                    ]),
                                const SizedBox(height: 24),
                                Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                        color: AppConstants.cardColor,
                                        borderRadius: BorderRadius.circular(24),
                                        border:
                                            Border.all(color: rentalBorder)),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                const RentalTag('Aylık plan',
                                                    icon: Icons
                                                        .calendar_month_outlined),
                                                RentalTag(
                                                    _active
                                                        ? (_status?['is_trial'] ==
                                                                true
                                                            ? 'Ücretsiz deneme aktif'
                                                            : 'Abonelik aktif')
                                                        : 'Abonelik gerekli',
                                                    accent: _active,
                                                    icon:
                                                        Icons.verified_outlined)
                                              ]),
                                          const SizedBox(height: 20),
                                          Text(_title,
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 10),
                                          if (_loading)
                                            const LinearProgressIndicator()
                                          else if (_product != null)
                                            Wrap(
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                spacing: 8,
                                                children: [
                                                  Text(_product!.price,
                                                      style: const TextStyle(
                                                          fontSize: 32,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: AppConstants
                                                              .primaryColor)),
                                                  const Text('/ ay',
                                                      style: TextStyle(
                                                          color: rentalMuted))
                                                ])
                                          else
                                            const Text(
                                                'Fiyat şu anda alınamıyor',
                                                style: TextStyle(
                                                    fontSize: 18,
                                                    color: rentalMuted)),
                                          const SizedBox(height: 18),
                                          const Divider(color: rentalBorder),
                                          const SizedBox(height: 12),
                                          for (final feature in _features)
                                            _feature(feature),
                                          if (_status?['access_end'] != null ||
                                              _status?['subscription_end'] !=
                                                  null)
                                            Text(
                                                'Erişim bitişi: ${_status?['access_end'] ?? _status?['subscription_end']}',
                                                style: const TextStyle(
                                                    color: rentalMuted,
                                                    fontSize: 12)),
                                        ])),
                                const SizedBox(height: 20),
                                if (_busy) const LinearProgressIndicator(),
                                if (!_store.supported)
                                  _message(
                                      'Ödeme ve geri yükleme için iPhone veya Android uygulamasını aç. Web üzerinden mağaza ödemesi yapılamaz.',
                                      rentalMuted),
                                if (_error != null)
                                  _message(_error!, Colors.redAccent),
                                if (_notice != null)
                                  _message(_notice!, AppConstants.primaryColor),
                                FilledButton.icon(
                                    onPressed: !_store.supported ||
                                            _busy ||
                                            _loading ||
                                            _product == null ||
                                            _status == null ||
                                            _active &&
                                                _status?['is_trial'] != true
                                        ? null
                                        : _buy,
                                    style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(54)),
                                    icon: const Icon(Icons.lock_outline_rounded,
                                        size: 19),
                                    label: Text(_active &&
                                            _status?['is_trial'] != true
                                        ? 'Aboneliğin aktif'
                                        : _product == null
                                            ? 'Aylık abone ol'
                                            : '${_product!.price} / ay • Abone ol')),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                    onPressed:
                                        !_store.supported || _busy || _loading
                                            ? null
                                            : _restore,
                                    child: const Text(
                                        'Satın alımları geri yükle')),
                                TextButton(
                                    onPressed: _busy ? null : _load,
                                    child:
                                        const Text('Abonelik durumunu yenile')),
                                if (_store.supported)
                                  TextButton(
                                      onPressed: () => _link(_store.platform ==
                                              'apple'
                                          ? 'https://apps.apple.com/account/subscriptions'
                                          : 'https://play.google.com/store/account/subscriptions?package=com.oto.tag&sku=$_productId'),
                                      child: const Text(
                                          'Mağazada aboneliği yönet / iptal et')),
                                const SizedBox(height: 12),
                                const Text(
                                    'Aylık abonelik iptal edilene kadar otomatik yenilenir. Fiyat ve ödeme onayı Apple App Store veya Google Play ekranında gösterilir. İptal edildiğinde erişim, ödenmiş dönemin sonuna kadar devam eder.',
                                    style: TextStyle(
                                        color: rentalMuted,
                                        fontSize: 12,
                                        height: 1.6)),
                                if (!widget.premium)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                          _business
                                              ? widget.userType == 'rentacar'
                                                  ? 'Mevcut rezervasyon, geçmiş ve şikayetler üyelik bitse de erişilebilir. Üyelik puan veya rozet kazandırmaz.'
                                                  : 'Üyelik puan veya rozet kazandırmaz. Mevcut iş ve geçmiş kayıtlarınız korunur.'
                                              : 'Canlı teşhis için uyumlu adaptör gerekir. Arıza kodu sözlüğü ücretsizdir.',
                                          style: const TextStyle(
                                              color: rentalMuted,
                                              fontSize: 12,
                                              height: 1.6))),
                                Wrap(spacing: 8, children: [
                                  TextButton(
                                      onPressed: () => _link(
                                          'https://eliteagency.sbs/gizlilik_politikasi.html'),
                                      child: const Text('Gizlilik politikası')),
                                  TextButton(
                                      onPressed: () => _link(
                                          'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
                                      child: const Text('Kullanım koşulları'))
                                ]),
                              ])))))));
  Widget _message(String text, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: TextStyle(color: color, height: 1.5)));
  Widget _feature(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.check_circle_outline,
            size: 19, color: AppConstants.primaryColor),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5)))
      ]));
}
