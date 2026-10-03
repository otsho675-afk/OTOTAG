import 'package:flutter/material.dart';
import '../services/rental_service.dart';
import 'rental_market_style.dart';

class RentalReviewEditor extends StatefulWidget {
  const RentalReviewEditor(
      {super.key, required this.jobId, required this.service});
  final int jobId;
  final RentalService service;
  @override
  State<RentalReviewEditor> createState() => _RentalReviewEditorState();
}

class _RentalReviewEditorState extends State<RentalReviewEditor> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_rating == 0) {
      setState(() => _error = 'Önce yıldız seçin.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.review(widget.jobId, _rating, _comment.text.trim());
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

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: PopScope(
          canPop: !_saving,
          child: SafeArea(
              child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      20, 24, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Kiralamayı değerlendir',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                            'Rezervasyon #${widget.jobId} • Her kiralamaya tek değerlendirme.',
                            style: const TextStyle(
                                color: rentalMuted, height: 1.5)),
                        const SizedBox(height: 16),
                        Wrap(
                            alignment: WrapAlignment.center,
                            children: List.generate(
                                5,
                                (i) => IconButton(
                                    tooltip: '${i + 1} yıldız',
                                    onPressed: _saving
                                        ? null
                                        : () => setState(() => _rating = i + 1),
                                    constraints: const BoxConstraints(
                                        minWidth: 48, minHeight: 48),
                                    icon: Icon(
                                        i < _rating
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                        size: 34,
                                        color: const Color(0xFFFFD071))))),
                        const SizedBox(height: 16),
                        TextField(
                            controller: _comment,
                            enabled: !_saving,
                            minLines: 3,
                            maxLines: 6,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                                labelText: 'Yorumun (isteğe bağlı)',
                                hintText:
                                    'Teslim, araç ve firma deneyimini paylaş.')),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.redAccent))),
                        FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(_saving
                                ? 'Kaydediliyor…'
                                : 'Değerlendirmeyi kaydet')),
                        TextButton(
                            onPressed:
                                _saving ? null : () => Navigator.pop(context),
                            child: const Text('Vazgeç')),
                      ])))));
}
