import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_constants.dart';

class VehicleKilometerUpdateDialog extends StatefulWidget {
  const VehicleKilometerUpdateDialog({
    super.key,
    required this.currentKm,
    required this.onSave,
    this.maintenanceTargetKm,
    this.vehicleName,
    this.plate,
  });

  final int currentKm;
  final int? maintenanceTargetKm;
  final String? vehicleName;
  final String? plate;
  final Future<String?> Function(int currentKm) onSave;

  @override
  State<VehicleKilometerUpdateDialog> createState() =>
      _VehicleKilometerUpdateDialogState();
}

class _VehicleKilometerUpdateDialogState
    extends State<VehicleKilometerUpdateDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _numberFormat = NumberFormat.decimalPattern('tr_TR');
  bool _isSaving = false;
  String? _error;

  int? get _enteredKm => int.tryParse(_controller.text.trim());
  int get _difference => (_enteredKm ?? widget.currentKm) - widget.currentKm;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.currentKm.toString();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _controller.addListener(_handleChanged);
  }

  void _handleChanged() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    super.dispose();
  }

  void _applyQuickIncrease(int amount) {
    HapticFeedback.selectionClick();
    final value = widget.currentKm + amount;
    _controller.value = TextEditingValue(
      text: value.toString(),
      selection: TextSelection.collapsed(offset: value.toString().length),
    );
  }

  Future<bool> _confirmLargeJump(int newKm) async {
    final difference = newKm - widget.currentKm;
    if (difference <= 50000) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF15181D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB547)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Yüksek KM artışı',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Text(
          'Tek seferde ${_numberFormat.format(difference)} km artış girdiniz. '
          'Değer doğruysa kaydetmeye devam edebilirsiniz.',
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Tekrar kontrol et'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFB547),
              foregroundColor: Colors.black,
            ),
            child: const Text('Değer doğru'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    final newKm = _enteredKm;
    if (newKm == null) return;
    if (!await _confirmLargeJump(newKm) || !mounted) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    String? error;
    try {
      error = await widget.onSave(newKm);
    } catch (_) {
      error = 'Kilometre kaydedilemedi. Lütfen tekrar deneyin.';
    }
    if (!mounted) return;
    if (error == null) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _error = error;
      });
    }
  }

  Color get _differenceColor {
    if (_difference < 0) return const Color(0xFFFF586B);
    if (_difference > 20000) return const Color(0xFFFFB547);
    return AppConstants.primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final entered = _enteredKm;
    final maintenanceTarget = widget.maintenanceTargetKm;
    final remainingToMaintenance =
        entered != null && maintenanceTarget != null && maintenanceTarget > 0
            ? maintenanceTarget - entered
            : null;
    final vehicleName = (widget.vehicleName ?? '').trim();
    final plate = (widget.plate ?? '').trim().toUpperCase();

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF191D22), Color(0xFF0B0E11)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppConstants.primaryColor.withValues(alpha: .20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .55),
                  blurRadius: 46,
                  offset: const Offset(0, 22),
                ),
                BoxShadow(
                  color: AppConstants.primaryColor.withValues(alpha: .045),
                  blurRadius: 34,
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                18 + MediaQuery.viewInsetsOf(context).bottom * .16,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppConstants.primaryColor.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: AppConstants.primaryColor.withValues(alpha: .18),
                            ),
                          ),
                          child: const Icon(
                            Icons.speed_rounded,
                            color: AppConstants.primaryColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'AKILLI KM ASİSTANI',
                                style: TextStyle(
                                  color: AppConstants.primaryColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                vehicleName.isEmpty ? 'Kilometreyi güncelle' : vehicleName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.35,
                                ),
                              ),
                              if (plate.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  plate,
                                  style: const TextStyle(
                                    color: AppConstants.mutedColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kapat',
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .035),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: .07)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _Metric(
                              label: 'KAYITLI KM',
                              value: _numberFormat.format(widget.currentKm),
                            ),
                          ),
                          Container(width: 1, height: 38, color: Colors.white10),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _Metric(
                              label: 'DEĞİŞİM',
                              value: _difference == 0
                                  ? '—'
                                  : '${_difference > 0 ? '+' : ''}${_numberFormat.format(_difference)}',
                              valueColor: _differenceColor,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .2,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Güncel kilometre',
                        hintText: widget.currentKm.toString(),
                        prefixIcon: const Icon(
                          Icons.pin_rounded,
                          color: AppConstants.primaryColor,
                        ),
                        suffixText: 'KM',
                        suffixStyle: const TextStyle(
                          color: AppConstants.primaryColor,
                          fontWeight: FontWeight.w900,
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: .20),
                        labelStyle: const TextStyle(color: AppConstants.mutedColor),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: .10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: const BorderSide(
                            color: AppConstants.primaryColor,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: const BorderSide(color: Color(0xFFFF586B)),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: const BorderSide(color: Color(0xFFFF586B)),
                        ),
                        errorMaxLines: 2,
                      ),
                      validator: (value) {
                        final km = int.tryParse(value ?? '');
                        if (km == null) return 'Güncel kilometreyi girin.';
                        if (km < widget.currentKm) {
                          return 'Kilometre kayıtlı değerden küçük olamaz.';
                        }
                        if (km == widget.currentKm) {
                          return 'Yeni kilometre kayıtlı değerle aynı.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 13),
                    const Text(
                      'HIZLI ARTIŞ',
                      style: TextStyle(
                        color: AppConstants.subtleTextColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .9,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [100, 250, 500, 1000, 5000]
                          .map((amount) => ActionChip(
                                onPressed: _isSaving
                                    ? null
                                    : () => _applyQuickIncrease(amount),
                                avatar: const Icon(
                                  Icons.add_rounded,
                                  size: 15,
                                  color: AppConstants.primaryColor,
                                ),
                                label: Text(
                                  '${_numberFormat.format(amount)} km',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                backgroundColor: Colors.white.withValues(alpha: .04),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: .08),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ))
                          .toList(),
                    ),
                    if (remainingToMaintenance != null) ...[
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: (remainingToMaintenance <= 0
                                  ? const Color(0xFFFF586B)
                                  : remainingToMaintenance <= 1000
                                      ? const Color(0xFFFFB547)
                                      : AppConstants.primaryColor)
                              .withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: (remainingToMaintenance <= 0
                                    ? const Color(0xFFFF586B)
                                    : remainingToMaintenance <= 1000
                                        ? const Color(0xFFFFB547)
                                        : AppConstants.primaryColor)
                                .withValues(alpha: .16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              remainingToMaintenance <= 0
                                  ? Icons.build_circle_rounded
                                  : Icons.route_rounded,
                              size: 19,
                              color: remainingToMaintenance <= 0
                                  ? const Color(0xFFFF586B)
                                  : remainingToMaintenance <= 1000
                                      ? const Color(0xFFFFB547)
                                      : AppConstants.primaryColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                remainingToMaintenance <= 0
                                    ? 'Bakım hedefi ${_numberFormat.format(remainingToMaintenance.abs())} km aşılmış görünüyor.'
                                    : 'Bakım hedefine yaklaşık ${_numberFormat.format(remainingToMaintenance)} km kaldı.',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_difference > 20000) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Bu artış normalden yüksek görünüyor. Kaydetmeden önce değeri kontrol edin.',
                        style: TextStyle(
                          color: Color(0xFFFFB547),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFF586B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          foregroundColor: const Color(0xFF03130D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _isSaving ? 'Kaydediliyor…' : 'Kilometreyi Güncelle',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppConstants.subtleTextColor,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -.3,
            ),
          ),
        ],
      );
}
