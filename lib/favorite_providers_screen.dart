// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'core/theme/app_palette.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/constants/app_constants.dart';
import 'provider_profile_screen.dart';
import 'services/authenticated_http_client.dart';

class FavoriteProvidersScreen extends StatefulWidget {
  const FavoriteProvidersScreen({super.key});

  @override
  State<FavoriteProvidersScreen> createState() =>
      _FavoriteProvidersScreenState();
}

class _FavoriteProvidersScreenState extends State<FavoriteProvidersScreen> {
  late final AuthenticatedHttpClient _client =
      AuthenticatedHttpClient(http.Client());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _providers = [];

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
      final uri = Uri.parse(AppConstants.baseUrl)
          .replace(queryParameters: {'action': 'get_favorite_providers'});
      final response =
          await _client.get(uri).timeout(Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          data is! Map ||
          data['status'] != 'success') {
        throw Exception(data is Map
            ? data['message']?.toString() ?? 'Favoriler alınamadı.'
            : 'Favoriler alınamadı.');
      }
      if (!mounted) return;
      setState(() {
        _providers = (data['providers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(int providerId) async {
    final uri = Uri.parse(AppConstants.baseUrl)
        .replace(queryParameters: {'action': 'toggle_favorite_provider'});
    final response = await _client.post(uri,
        body: {'provider_id': providerId.toString()}).timeout(
      Duration(seconds: 15),
    );
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200 &&
        data is Map &&
        data['status'] == 'success') {
      await _load();
    }
  }

  String _service(String? value) {
    switch (value) {
      case 'mechanic':
        return 'Tamirci';
      case 'tow':
        return 'Çekici';
      case 'tire':
        return 'Lastikçi';
      case 'wash':
        return 'Oto Yıkama';
      default:
        return 'Usta';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        title: Text('Favori Ustalarım'),
        backgroundColor: AppPalette.page,
        foregroundColor: AppPalette.text,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_loading) LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.redAccent)),
              ),
            if (!_loading && _providers.isEmpty && _error == null)
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(22),
                  border:
                      Border.all(color: AppPalette.text.withValues(alpha: .07)),
                ),
                child: Column(children: [
                  Icon(Icons.favorite_border_rounded,
                      color: AppPalette.accent, size: 40),
                  SizedBox(height: 12),
                  Text('Henüz favori ustan yok',
                      style: TextStyle(
                          color: AppPalette.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                  SizedBox(height: 6),
                  Text(
                    'Memnun kaldığın ustaları favoriye eklediğinde burada görebilirsin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.muted, height: 1.4),
                  ),
                ]),
              ),
            for (final provider in _providers)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: AppPalette.text.withValues(alpha: .07)),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor:
                        AppPalette.accent.withValues(alpha: .12),
                    child: Icon(Icons.engineering_rounded,
                        color: AppPalette.accent),
                  ),
                  title: Row(children: [
                    Flexible(
                      child: Text(
                        provider['name']?.toString() ?? 'Usta',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (provider['verified'] == true) ...[
                      SizedBox(width: 6),
                      Icon(Icons.verified_rounded,
                          color: AppPalette.accent, size: 17),
                    ],
                  ]),
                  subtitle: Text(
                    '${_service(provider['service_category']?.toString())} • ${provider['city'] ?? ''} • ★ ${provider['rating'] ?? '0.0'}',
                    style: TextStyle(color: AppPalette.muted, fontSize: 12),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProviderProfileScreen(
                        providerId:
                            int.tryParse('${provider['id']}') ?? 0,
                      ),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Favoriden çıkar',
                    onPressed: () =>
                        _remove(int.tryParse('${provider['id']}') ?? 0),
                    icon: Icon(Icons.favorite_rounded,
                        color: Colors.redAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
