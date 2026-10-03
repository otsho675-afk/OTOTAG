import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../services/app_update_service.dart';

class AdminUpdatePanel extends StatefulWidget {
  const AdminUpdatePanel({super.key, this.service});
  final AppUpdateService? service;
  @override
  State<AdminUpdatePanel> createState() => AdminUpdatePanelState();
}

class AdminUpdatePanelState extends State<AdminUpdatePanel> {
  late final _service = widget.service ?? AppUpdateService();
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Ototag güncellemesi hazır');
  final _message = TextEditingController();
  final _androidVersion = TextEditingController(),
      _iosVersion = TextEditingController();
  final _androidBuild = TextEditingController(),
      _iosBuild = TextEditingController();
  final _androidUrl = TextEditingController(
      text:
          'https://play.google.com/store/apps/details?id=${AppConstants.androidPackageName}');
  final _iosUrl = TextEditingController();
  AppUpdateSettings? _settings;
  bool _loading = true, _busy = false, _required = false;
  String _target = 'all';
  String? _error, _requestKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _service.adminSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
      });
      if (_iosUrl.text.isEmpty) {
        _iosUrl.text = settings.updates['ios']?.storeUrl ?? '';
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _errorText(e);
        });
      }
    }
  }

  String _errorText(Object error) => error is FormatException
      ? error.message
      : 'İşlem tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin.';
  void _changed(String _) => _requestKey = null;
  Map<String, String> _body() => {
        'request_key': _requestKey ??= AppUpdateService.requestKey(),
        'target': _target,
        'title': _title.text.trim(),
        'message': _message.text.trim(),
        'required_update': _required ? '1' : '0',
        'android_version': _androidVersion.text.trim(),
        'ios_version': _iosVersion.text.trim(),
        'android_build':
            _androidBuild.text.trim().isEmpty ? '0' : _androidBuild.text.trim(),
        'ios_build':
            _iosBuild.text.trim().isEmpty ? '0' : _iosBuild.text.trim(),
        'android_store_url': _androidUrl.text.trim(),
        'ios_store_url': _iosUrl.text.trim(),
      };

  Future<void> _preview() async {
    if (_busy || !_form.currentState!.validate()) return;
    final body = _body();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Güncelleme duyurusu önizlemesi'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(body['title']!,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Text(body['message']!),
                    const SizedBox(height: 16),
                    for (final platform
                        in _target == 'all' ? ['android', 'ios'] : [_target])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '${platform == 'ios' ? 'iPhone' : 'Android'}: ${body['${platform}_version']} • Derleme ${body['${platform}_build']}')),
                    Text(_required
                        ? 'Zorunlu: Eski sürüm kullananlar güncellemeden devam edemez.'
                        : 'İsteğe bağlı: Kullanıcılar 24 saat erteleyebilir.'),
                    const SizedBox(height: 12),
                    const Text(
                        'Duyuru yayımlanır ve seçilen platformlarda bildirim izni olan cihazlara gönderilir. Modal yalnızca eski sürümlerde görünür.'),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Düzenle')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Yayımla ve bildir'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    await _operation(() => _service.publish(body));
  }

  Future<void> _operation(Future<AppUpdateSettings> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await action();
      if (!mounted) return;
      setState(() => _settings = settings);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(settings.message)));
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(AppRelease release) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Duyuruyu geri çek'),
              content: Text(
                  '${release.platform == 'ios' ? 'iPhone' : 'Android'} ${release.displayVersion} duyurusu kapatılacak. Telefonlar bir sonraki başarılı kontrolde güncelleme modalını kapatır. Gönderilmiş bildirimler geri alınamaz.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Vazgeç')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Geri çek'))
              ],
            ));
    if (confirmed == true && mounted) {
      await _operation(() => _service.withdraw(release.id));
    }
  }

  Widget _field(String label, TextEditingController controller,
          {String? hint,
          String? Function(String?)? validator,
          int maxLines = 1,
          int? maxLength,
          TextInputType? keyboardType}) =>
      TextFormField(
          controller: controller,
          onChanged: _changed,
          enabled: !_busy,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: validator ??
              (value) =>
                  (value ?? '').trim().isEmpty ? 'Bu alanı doldurun.' : null);

  Widget _platformForm(String platform) {
    final android = platform == 'android';
    final version = android ? _androidVersion : _iosVersion;
    final build = android ? _androidBuild : _iosBuild;
    final url = android ? _androidUrl : _iosUrl;
    final active = _settings?.updates[platform];
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(android ? 'Android / Google Play' : 'iPhone / App Store',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(active == null
          ? 'Henüz yayımlanmış duyuru yok.'
          : 'Yayındaki sürüm: ${active.displayVersion}'),
      const SizedBox(height: 16),
      _field(android ? 'Android sürümü' : 'iPhone sürümü', version,
          hint: 'Örn. 1.0.1',
          validator: (value) =>
              RegExp(r'^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})$')
                      .hasMatch((value ?? '').trim())
                  ? null
                  : '1.0.1 biçiminde sürüm girin.'),
      const SizedBox(height: 12),
      _field(
          android
              ? 'Android derleme numarası (isteğe bağlı)'
              : 'iPhone derleme numarası (isteğe bağlı)',
          build,
          hint: 'Örn. 71',
          keyboardType: TextInputType.number, validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return null;
        final number = int.tryParse(text);
        return number != null &&
                number >= 0 &&
                number <= 2147483647 &&
                RegExp(r'^\d+$').hasMatch(text)
            ? null
            : 'Geçerli bir tam sayı girin.';
      }),
      const SizedBox(height: 12),
      _field(android ? 'Google Play bağlantısı' : 'App Store bağlantısı', url,
          keyboardType: TextInputType.url,
          validator: (value) => AppRelease(
                          id: 0,
                          platform: platform,
                          version: '0.0.0',
                          buildNumber: 0,
                          title: '',
                          message: '',
                          storeUrl: (value ?? '').trim(),
                          requiredUpdate: false,
                          active: true)
                      .safeStoreUri !=
                  null
              ? null
              : 'Uygulamanın geçerli mağaza bağlantısını girin.'),
    ]));
  }

  Widget _card(Widget child) => Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: child));

  String _pushLabel(AppRelease release) => switch (release.pushStatus) {
        'sent' => 'Gönderim kabul edildi',
        'no_subscribers' => 'Bildirim alabilen cihaz yok',
        'not_configured' => 'Bildirim ayarı eksik',
        'failed' => 'Gönderim başarısız',
        'sending' => 'Gönderiliyor',
        _ => 'Gönderim bekliyor',
      };

  Widget _historyCard(AppRelease release) =>
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Text(
              '${release.platform == 'ios' ? 'iPhone' : 'Android'} • ${release.displayVersion}',
              style: Theme.of(context).textTheme.titleMedium),
          Chip(label: Text(release.active ? 'Yayında' : 'Yayında değil')),
          if (release.requiredUpdate) const Chip(label: Text('Zorunlu')),
        ]),
        Text(release.title),
        const SizedBox(height: 6),
        Text(_pushLabel(release),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (release.pushDetail.isNotEmpty) Text(release.pushDetail),
        if (release.createdAt.isNotEmpty)
          Text('Yayımlanma: ${release.createdAt}',
              style: Theme.of(context).textTheme.bodySmall),
        if (release.active)
          Wrap(spacing: 8, runSpacing: 4, children: [
            TextButton.icon(
                onPressed: _busy ? null : () => _withdraw(release),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Duyuruyu geri çek')),
            if (['failed', 'not_configured'].contains(release.pushStatus) &&
                release.pushAttempts < 5)
              TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _operation(() => _service.retryPush(release.id)),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Bildirimi yeniden dene')),
          ]),
      ]));

  @override
  Widget build(BuildContext context) {
    if (_loading && _settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Sürüm ve güncelleme yönetimi',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        const Text(
                            'Mağazada yayımlanan sürümü girin. Sistem duyuruyu kaydeder, telefonlara bildirim gönderir ve eski sürümlerde güncelleme modalını açar.'),
                        const SizedBox(height: 16),
                        if (_settings?.notificationHealth
                            case final Map<String, dynamic> health)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _card(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Telefon bildirimleri ve hatırlatmalar',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 8),
                                    Text(
                                        health['worker_recent'] == true
                                            ? 'Otomatik gönderim görevi çalışıyor.'
                                            : 'Otomatik gönderim görevi çalışmıyor veya son kontrol gecikti.',
                                        style: TextStyle(
                                            color:
                                                health['worker_recent'] == true
                                                    ? AppConstants.primaryColor
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .error)),
                                    const SizedBox(height: 8),
                                    Text(
                                        'Bekleyen: ${health['pending']} • Yeniden denenecek: ${health['failed']}'),
                                    Text(
                                        'Servisin kabul ettiği: ${health['accepted']} • Uygun cihaz yok: ${health['no_subscribers']}'),
                                    if (health['last_issue'] != null)
                                      Text('${health['last_issue']}'),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Servisin kabul etmesi, telefonun teslim aldığı anlamına gelmez. Kullanıcının bildirim izni ve cihaz bağlantısı gerekir.',
                                        style: TextStyle(fontSize: 12)),
                                  ]))),
                        if (_error != null)
                          _card(Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                                if (_settings == null)
                                  TextButton(
                                      onPressed: _load,
                                      child: const Text('Tekrar dene')),
                              ])),
                        if (_settings != null && !_settings!.pushConfigured)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _card(const Text(
                                  'Telefon bildirimi için sunucuda OneSignal yapılandırması eksik. Güncelleme modalı, uygulamanın sunucu kontrolüyle yine çalışır.'))),
                        if (_settings != null)
                          Form(
                              key: _form,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                        initialValue: _target,
                                        decoration: const InputDecoration(
                                            labelText: 'Hangi telefonlara?'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'all',
                                              child: Text('Android ve iPhone')),
                                          DropdownMenuItem(
                                              value: 'android',
                                              child: Text('Yalnızca Android')),
                                          DropdownMenuItem(
                                              value: 'ios',
                                              child: Text('Yalnızca iPhone'))
                                        ],
                                        onChanged: _busy
                                            ? null
                                            : (value) => setState(() {
                                                  _target = value!;
                                                  _requestKey = null;
                                                })),
                                    const SizedBox(height: 16),
                                    LayoutBuilder(
                                        builder: (context, constraints) {
                                      final forms = [
                                        if (_target != 'ios')
                                          _platformForm('android'),
                                        if (_target != 'android')
                                          _platformForm('ios')
                                      ];
                                      if (forms.length == 2 &&
                                          constraints.maxWidth >= 700) {
                                        return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: forms[0]),
                                              const SizedBox(width: 16),
                                              Expanded(child: forms[1])
                                            ]);
                                      }
                                      return Column(children: [
                                        for (var i = 0;
                                            i < forms.length;
                                            i++) ...[
                                          if (i > 0) const SizedBox(height: 16),
                                          forms[i]
                                        ]
                                      ]);
                                    }),
                                    const SizedBox(height: 16),
                                    _card(Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _field('Duyuru başlığı', _title,
                                              maxLength: 50),
                                          const SizedBox(height: 12),
                                          _field('Yenilikler / duyuru metni',
                                              _message,
                                              maxLines: 4, maxLength: 1500),
                                          SwitchListTile.adaptive(
                                              contentPadding: EdgeInsets.zero,
                                              title: const Text(
                                                  'Zorunlu güncelleme'),
                                              subtitle: const Text(
                                                  'Açılırsa eski sürümlerde “Daha sonra” seçeneği gösterilmez.'),
                                              value: _required,
                                              onChanged: _busy
                                                  ? null
                                                  : (value) => setState(() {
                                                        _required = value;
                                                        _requestKey = null;
                                                      })),
                                          const SizedBox(height: 12),
                                          FilledButton.icon(
                                              onPressed:
                                                  _busy ? null : _preview,
                                              icon: Icon(_busy
                                                  ? Icons.hourglass_top_rounded
                                                  : Icons.visibility_outlined),
                                              label: Text(_busy
                                                  ? 'İşlem sürüyor…'
                                                  : 'Önizle ve yayımla')),
                                        ])),
                                  ])),
                        const SizedBox(height: 24),
                        Text('Son duyurular',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        if (_settings?.history.isEmpty ?? true)
                          const Text('Henüz güncelleme duyurusu yayımlanmadı.'),
                        for (final release
                            in _settings?.history ?? <AppRelease>[]) ...[
                          _historyCard(release),
                          const SizedBox(height: 12)
                        ],
                      ]))),
        ));
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _message,
      _androidVersion,
      _iosVersion,
      _androidBuild,
      _iosBuild,
      _androidUrl,
      _iosUrl
    ]) {
      controller.dispose();
    }
    if (widget.service == null) _service.dispose();
    super.dispose();
  }
}
