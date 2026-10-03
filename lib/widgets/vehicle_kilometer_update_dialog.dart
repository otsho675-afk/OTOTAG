import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VehicleKilometerUpdateDialog extends StatefulWidget {
  const VehicleKilometerUpdateDialog({
    super.key,
    required this.currentKm,
    required this.onSave,
  });

  final int currentKm;
  final Future<String?> Function(int currentKm) onSave;

  @override
  State<VehicleKilometerUpdateDialog> createState() =>
      _VehicleKilometerUpdateDialogState();
}

class _VehicleKilometerUpdateDialogState
    extends State<VehicleKilometerUpdateDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSave(int.parse(_controller.text));
    } catch (_) {
      error = 'Kilometre kaydedilemedi. Lütfen tekrar deneyin.';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        backgroundColor: const Color(0xFF161822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Güncel kilometre',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kayıtlı kilometre: ${widget.currentKm} km',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Güncel kilometre',
                    labelStyle: TextStyle(color: Colors.white70),
                    suffixText: 'km',
                    suffixStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                    errorMaxLines: 2,
                  ),
                  validator: (value) {
                    final km = int.tryParse(value ?? '');
                    if (km == null) return 'Güncel kilometreyi girin.';
                    if (km < widget.currentKm) {
                      return 'Kilometre kayıtlı değerden küçük olamaz.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00FFA3),
              foregroundColor: Colors.black,
            ),
            child: Text(_isSaving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}
