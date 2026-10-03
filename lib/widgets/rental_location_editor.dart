import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/rental_service.dart';
import 'rental_market_style.dart';
import 'rental_pickup_map.dart';

class RentalLocationEditor extends StatefulWidget {
  const RentalLocationEditor(
      {super.key,
      required this.service,
      required this.city,
      this.pickup,
      this.mapBuilder});
  final RentalService service;
  final String city;
  final Map<String, dynamic>? pickup;
  final Widget Function(LatLng, ValueChanged<LatLng>)? mapBuilder;
  @override
  State<RentalLocationEditor> createState() => _RentalLocationEditorState();
}

class _RentalLocationEditorState extends State<RentalLocationEditor> {
  final _form = GlobalKey<FormState>();
  late final _address =
      TextEditingController(text: '${widget.pickup?['address'] ?? ''}');
  late final _lat =
      TextEditingController(text: '${widget.pickup?['latitude'] ?? ''}');
  late final _lng =
      TextEditingController(text: '${widget.pickup?['longitude'] ?? ''}');
  String? _error;
  bool _busy = false;
  LatLng? get _point {
    final lat = double.tryParse(_lat.text), lng = double.tryParse(_lng.text);
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        (lat == 0 && lng == 0)) return null;
    return LatLng(lat, lng);
  }

  @override
  void dispose() {
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _select(LatLng point) {
    setState(() {
      _lat.text = '${point.latitude}';
      _lng.text = '${point.longitude}';
    });
  }

  Future<void> _locate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw const RentalException('Cihazın konum hizmetini açın.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw const RentalException(
            'Konum izni verilmedi. Haritadan teslim yerini seçebilirsiniz.');
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15));
      if (!mounted) return;
      _select(LatLng(position.latitude, position.longitude));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_point == null) {
      setState(() =>
          _error = 'Teslim yerini haritadan seçin veya konumunuzu kullanın.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.updateLocation(
          _point!.latitude, _point!.longitude, _address.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _point ?? const LatLng(39.0, 35.0);
    return Theme(
        data: rentalTheme(),
        child: PopScope(
            canPop: !_busy,
            child: SafeArea(
                child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 24, 20,
                        MediaQuery.viewInsetsOf(context).bottom + 24),
                    child: Form(
                        key: _form,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Araç teslim konumu',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(
                                  '${widget.city} • Müşterinin aracı teslim alacağı firma adresini seçin.',
                                  style: const TextStyle(
                                      color: rentalMuted, height: 1.5)),
                              const SizedBox(height: 16),
                              TextFormField(
                                  controller: _address,
                                  enabled: !_busy,
                                  minLines: 2,
                                  maxLines: 3,
                                  maxLength: 500,
                                  decoration: const InputDecoration(
                                      labelText: 'Açık teslim adresi'),
                                  validator: (s) => (s?.trim().length ?? 0) < 8
                                      ? 'Açık teslim adresini yazın.'
                                      : null),
                              OutlinedButton.icon(
                                  onPressed: _busy ? null : _locate,
                                  icon: const Icon(Icons.my_location),
                                  label: const Text('Konumumu kullan')),
                              const SizedBox(height: 12),
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SizedBox(
                                      height: 240,
                                      child: widget.mapBuilder
                                              ?.call(target, _select) ??
                                          RentalPickupMap(
                                              latitude: target.latitude,
                                              longitude: target.longitude,
                                              selected: _point != null,
                                              onSelect: _busy
                                                  ? null
                                                  : (lat, lng) => _select(
                                                      LatLng(lat, lng))))),
                              const SizedBox(height: 12),
                              const Text(
                                  'Haritaya dokunarak teslim noktasını seçebilirsin.',
                                  style: TextStyle(
                                      color: rentalMuted, fontSize: 12)),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                    child: TextFormField(
                                        controller: _lat,
                                        enabled: !_busy,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                            decimal: true, signed: true),
                                        decoration: const InputDecoration(
                                            labelText: 'Enlem'),
                                        onChanged: (_) => setState(() {}))),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: TextFormField(
                                        controller: _lng,
                                        enabled: !_busy,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                            decimal: true, signed: true),
                                        decoration: const InputDecoration(
                                            labelText: 'Boylam'),
                                        onChanged: (_) => setState(() {}))),
                              ]),
                              const SizedBox(height: 12),
                              const Text(
                                  'Konum değişikliği yeni rezervasyonlarda geçerlidir. Mevcut rezervasyonun teslim adresi korunur.',
                                  style: TextStyle(
                                      color: rentalMuted,
                                      fontSize: 12,
                                      height: 1.5)),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: Colors.redAccent))),
                              const SizedBox(height: 16),
                              FilledButton(
                                  onPressed: _busy ? null : _save,
                                  child: Text(_busy
                                      ? 'İşleniyor…'
                                      : 'Teslim konumunu kaydet')),
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: const Text('Vazgeç')),
                            ]))))));
  }
}
