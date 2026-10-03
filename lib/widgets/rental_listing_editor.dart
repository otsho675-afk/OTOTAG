import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/car_data.dart';
import '../services/rental_service.dart';
import 'rental_market_style.dart';

class RentalListingEditor extends StatefulWidget {
  const RentalListingEditor(
      {super.key,
      required this.companyId,
      required this.city,
      required this.service,
      this.listing,
      required this.plateFormatter});
  final int companyId;
  final String city;
  final RentalService service;
  final Map<String, dynamic>? listing;
  final TextInputFormatter plateFormatter;
  @override
  State<RentalListingEditor> createState() => _RentalListingEditorState();
}

class _RentalListingEditorState extends State<RentalListingEditor> {
  final _form = GlobalKey<FormState>();
  late final _plate =
      TextEditingController(text: '${widget.listing?['plate'] ?? ''}');
  late final _price =
      TextEditingController(text: '${widget.listing?['daily_price'] ?? ''}');
  late final _description =
      TextEditingController(text: '${widget.listing?['description'] ?? ''}');
  String? _brand, _model, _year, _error;
  final _bytes = <int, Uint8List>{};
  final _names = <int, String>{};
  final _removed = <int>{};
  bool _saving = false, _picking = false;

  @override
  void initState() {
    super.initState();
    final car = widget.listing;
    if (car == null) return;
    _brand = car['brand']?.toString();
    _model = car['model']?.toString();
    final label = '${car['car_brand_model'] ?? ''}';
    if (_brand == null || _brand!.isEmpty) {
      for (final make in CarData.makesAndModels.keys) {
        if (label.toLowerCase().startsWith('${make.toLowerCase()} ')) {
          _brand = make;
          _model = label.substring(make.length).trim();
          break;
        }
      }
    }
    final year = '${car['model_year'] ?? ''}';
    if (int.tryParse(year) != null) _year = year;
  }

  @override
  void dispose() {
    _plate.dispose();
    _price.dispose();
    _description.dispose();
    super.dispose();
  }

  String _oldPhoto(int index) {
    final car = widget.listing;
    if (car == null || _removed.contains(index)) return '';
    return (car['photo${index + 1}'] ??
            (index == 0 ? car['photo'] : null) ??
            '')
        .toString();
  }

  Future<void> _pick(int index) async {
    if (_saving || _picking) return;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const RentalException('Her fotoğraf en fazla 5 MB olabilir.');
      }
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _bytes[index] = bytes;
          _names[index] = file.name;
          _removed.remove(index);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fields = <String, String>{
        'company_id': '${widget.companyId}',
        'brand': _brand!,
        'model': _model!,
        'model_year': _year!,
        'plate': _plate.text.trim(),
        'daily_price': _price.text.trim().replaceAll(',', '.'),
        'description': _description.text.trim(),
        for (final i in _removed) 'remove_photo_${i + 1}': '1'
      };
      final photos = [
        for (final i in _bytes.keys)
          http.MultipartFile.fromBytes('image_${i + 1}', _bytes[i]!,
              filename: _names[i] ?? 'car.jpg')
      ];
      await widget.service
          .saveListing(fields, listing: widget.listing, images: photos);
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photo(int i) {
    final old = _oldPhoto(i);
    final present = _bytes.containsKey(i) || old.isNotEmpty;
    return Expanded(
        child: Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 10),
            child: AspectRatio(
                aspectRatio: 1,
                child: Stack(fit: StackFit.expand, children: [
                  Material(
                      color: rentalField,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                          onTap: _saving || _picking ? null : () => _pick(i),
                          child: _bytes.containsKey(i)
                              ? Image.memory(_bytes[i]!, fit: BoxFit.cover)
                              : old.isNotEmpty
                                  ? Image.network(
                                      Uri.parse(AppConstants.baseMediaUrl)
                                          .resolve(old)
                                          .toString(),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.add_a_photo_outlined,
                                          color: rentalMuted))
                                  : const Icon(Icons.add_a_photo_outlined,
                                      color: rentalMuted))),
                  if (present)
                    Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                            tooltip: '${i + 1}. fotoğrafı kaldır',
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.black87),
                            icon: const Icon(Icons.close_rounded,
                                size: 17, color: Colors.white),
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      _bytes.remove(i);
                                      _names.remove(i);
                                      _removed.add(i);
                                    }))),
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    final makes =
        {if (_brand != null) _brand!, ...CarData.makesAndModels.keys}.toList();
    final models = {
      if (_model != null) _model!,
      ...CarData.makesAndModels[_brand] ?? <String>[]
    }.toList();
    final years = {
      if (_year != null) _year!,
      ...List.generate(DateTime.now().year + 2 - 1980,
          (i) => '${DateTime.now().year + 1 - i}')
    }.toList();
    return Theme(
        data: rentalTheme(),
        child: PopScope(
            canPop: !_saving,
            child: SafeArea(
                child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 20, 20,
                        MediaQuery.viewInsetsOf(context).bottom + 20),
                    child: Form(
                        key: _form,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        widget.listing == null
                                            ? 'Yeni Kiralık Araç Ekle'
                                            : 'Aracı düzenle',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 21,
                                            fontWeight: FontWeight.w700))),
                                IconButton(
                                    tooltip: 'Kapat',
                                    onPressed: _saving
                                        ? null
                                        : () => Navigator.pop(context, false),
                                    icon: const Icon(Icons.close_rounded))
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                  '${widget.city} • İlan müşterilere firmanın günlük fiyatıyla gösterilir.',
                                  style: const TextStyle(
                                      color: rentalMuted,
                                      fontSize: 12,
                                      height: 1.5)),
                              const SizedBox(height: 20),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: DropdownButtonFormField<String>(
                                            initialValue: _brand,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Marka'),
                                            menuMaxHeight: 350,
                                            items: makes
                                                .map((s) => DropdownMenuItem(
                                                    value: s,
                                                    child: Text(s,
                                                        overflow: TextOverflow
                                                            .ellipsis)))
                                                .toList(),
                                            validator: (v) => v == null
                                                ? 'Marka seçin.'
                                                : null,
                                            onChanged: _saving
                                                ? null
                                                : (v) => setState(() {
                                                      _brand = v;
                                                      _model = null;
                                                    }))),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: DropdownButtonFormField<String>(
                                            key: ValueKey(_brand),
                                            initialValue: _model,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Model'),
                                            menuMaxHeight: 350,
                                            items: models
                                                .map((s) => DropdownMenuItem(
                                                    value: s,
                                                    child: Text(s,
                                                        overflow: TextOverflow
                                                            .ellipsis)))
                                                .toList(),
                                            validator: (v) => v == null
                                                ? 'Model seçin.'
                                                : null,
                                            onChanged: _saving || _brand == null
                                                ? null
                                                : (v) => setState(
                                                    () => _model = v))),
                                  ]),
                              const SizedBox(height: 14),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: TextFormField(
                                            controller: _plate,
                                            enabled: !_saving,
                                            textCapitalization:
                                                TextCapitalization.characters,
                                            inputFormatters: [
                                              widget.plateFormatter,
                                              LengthLimitingTextInputFormatter(
                                                  11)
                                            ],
                                            decoration: const InputDecoration(
                                                labelText: 'Plaka',
                                                hintText: '42 TAG 403'),
                                            validator: (v) =>
                                                RegExp(r'^(0[1-9]|[1-7][0-9]|8[01])[A-Z]{1,3}\d{2,4}$')
                                                        .hasMatch((v ?? '')
                                                            .replaceAll(' ', '')
                                                            .toUpperCase())
                                                    ? null
                                                    : 'Geçerli plaka girin.')),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: DropdownButtonFormField<String>(
                                            initialValue: _year,
                                            isExpanded: true,
                                            menuMaxHeight: 300,
                                            decoration: const InputDecoration(
                                                labelText: 'Model yılı'),
                                            items: years
                                                .map((s) => DropdownMenuItem(
                                                    value: s, child: Text(s)))
                                                .toList(),
                                            validator: (v) =>
                                                v == null ? 'Yıl seçin.' : null,
                                            onChanged: _saving
                                                ? null
                                                : (v) =>
                                                    setState(() => _year = v))),
                                  ]),
                              const SizedBox(height: 14),
                              TextFormField(
                                  controller: _price,
                                  enabled: !_saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Günlük kiralama ücreti',
                                      suffixText: '₺ / gün'),
                                  validator: (v) => rentalCents(v ?? '') == null
                                      ? 'Geçerli, pozitif bir ücret girin.'
                                      : null),
                              const SizedBox(height: 14),
                              TextFormField(
                                  controller: _description,
                                  enabled: !_saving,
                                  minLines: 2,
                                  maxLines: 3,
                                  maxLength: 4000,
                                  decoration: const InputDecoration(
                                      labelText: 'Araç özellikleri',
                                      hintText: 'Örn. otomatik vites, dizel')),
                              const SizedBox(height: 8),
                              const Text('Araç fotoğrafları',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              const Text(
                                  'En fazla 3 fotoğraf • JPEG, PNG veya WebP • 5 MB',
                                  style: TextStyle(
                                      color: rentalMuted, fontSize: 11)),
                              const SizedBox(height: 12),
                              Row(children: List.generate(3, _photo)),
                              if (widget.listing != null)
                                const Padding(
                                    padding: EdgeInsets.only(top: 14),
                                    child: Text(
                                        'Fiyat, plaka veya araç bilgisi değişirse bekleyen eski teklifler kapanır.',
                                        style: TextStyle(
                                            color: rentalMuted,
                                            fontSize: 12,
                                            height: 1.5))),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: Color(0xFFFF9DAD),
                                            height: 1.5))),
                              const SizedBox(height: 22),
                              const Text(
                                  'İlan fiyatını ve süreyi kabul eden müşteri doğrudan rezervasyon oluşturabilir. Toplam ücret günlük fiyat × gün sayısıdır.',
                                  style: TextStyle(
                                      color: rentalMuted,
                                      fontSize: 12,
                                      height: 1.5)),
                              const SizedBox(height: 12),
                              FilledButton(
                                  onPressed: _saving || _picking ? null : _save,
                                  child: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Text(widget.listing == null
                                          ? 'İlana Ekle'
                                          : 'Değişiklikleri kaydet')),
                            ]))))));
  }
}
