import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'core/constants/app_constants.dart';
import 'services/authenticated_http_client.dart';
import 'services/vehicle_deadline.dart';
import 'diagnostic_screen.dart';

class VehicleHealthScreen extends StatefulWidget {
  const VehicleHealthScreen({super.key, required this.customerId});
  final int customerId;
  @override
  State<VehicleHealthScreen> createState() => _VehicleHealthScreenState();
}

class _VehicleHealthScreenState extends State<VehicleHealthScreen> {
  late final AuthenticatedHttpClient _client =
      AuthenticatedHttpClient(http.Client());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];

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
    setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.parse(AppConstants.baseUrl).replace(queryParameters: {
        'action': 'sync_vehicle_reminders',
        'user_id': widget.customerId.toString(),
      });
      final response = await _client.get(uri);
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['status'] != 'success') {
        throw Exception(data is Map ? (data['message']?.toString() ?? 'Araç verileri alınamadı.') : 'Araç verileri alınamadı.');
      }
      if (!mounted) return;
      setState(() {
        _vehicles = (data['vehicles'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dateStatus(dynamic raw, String label) {
    final date = VehicleDeadline.parse(raw);
    if (date == null) return label + ': tarih girilmemiş';
    final days = VehicleDeadline(date).days;
    if (days == null) return label + ': bilinmiyor';
    if (days < 0) return label + ': ' + days.abs().toString() + ' gün gecikti';
    if (days == 0) return label + ': bugün';
    return label + ': ' + days.toString() + ' gün kaldı';
  }

  int _healthScore(Map<String, dynamic> v) {
    var score = 100;
    for (final key in ['insurance_date', 'inspection_date', 'mtv_date']) {
      final date = VehicleDeadline.parse(v[key]);
      final days = date == null ? null : VehicleDeadline(date).days;
      if (days == null) {
        score -= 5;
      } else if (days < 0) {
        score -= 25;
      } else if (days <= 7) {
        score -= 12;
      } else if (days <= 15) {
        score -= 6;
      }
    }
    final current = int.tryParse((v['current_km'] ?? 0).toString()) ?? 0;
    final maintenance = int.tryParse((v['maintenance_km'] ?? 0).toString()) ?? 0;
    if (maintenance > 0) {
      final remaining = maintenance - current;
      if (remaining <= 0) score -= 25;
      else if (remaining <= 1000) score -= 10;
    }
    return score.clamp(0, 100).toInt();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppConstants.bgColor,
    appBar: AppBar(
      title: const Text('Araç Sağlık Merkezi'),
      backgroundColor: AppConstants.bgColor,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          tooltip: 'OBD Arıza Tespit',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DiagnosticScreen(userType: 'customer'),
            ),
          ),
          icon: const Icon(Icons.settings_input_component_rounded),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          if (!_loading && _vehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                child: Text('Henüz araç eklenmemiş.', style: TextStyle(color: Colors.white60)),
              ),
            ),
          for (final vehicle in _vehicles) _vehicleCard(vehicle),
        ],
      ),
    ),
  );

  Widget _vehicleCard(Map<String, dynamic> v) {
    final score = _healthScore(v);
    final current = int.tryParse((v['current_km'] ?? 0).toString()) ?? 0;
    final maintenance = int.tryParse((v['maintenance_km'] ?? 0).toString()) ?? 0;
    final remaining = maintenance > 0 ? maintenance - current : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppConstants.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(
            backgroundColor: AppConstants.primaryColor,
            child: Icon(Icons.directions_car_rounded, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v['brand_model']?.toString() ?? 'Araç',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              Text(v['plate']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          Text(score.toString() + '/100',
              style: const TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w900, fontSize: 18)),
        ]),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: score / 100),
        const SizedBox(height: 16),
        _row(Icons.verified_user_outlined, _dateStatus(v['inspection_date'], 'Muayene')),
        _row(Icons.shield_outlined, _dateStatus(v['insurance_date'], 'Sigorta')),
        _row(Icons.receipt_long_outlined, _dateStatus(v['mtv_date'], 'MTV')),
        if (remaining != null)
          _row(Icons.build_circle_outlined,
              remaining <= 0
                  ? 'Bakım: ' + remaining.abs().toString() + ' km geçti'
                  : 'Bakım: yaklaşık ' + remaining.toString() + ' km kaldı'),
      ]),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(children: [
      Icon(icon, size: 18, color: AppConstants.primaryColor),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
    ]),
  );
}
