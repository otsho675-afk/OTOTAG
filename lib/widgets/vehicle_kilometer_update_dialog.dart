// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import '../core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';



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
        backgroundColor: AppPalette.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB547)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Yüksek KM artışı',
                style: TextStyle(color: AppPalette.text, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Text(
          'Tek seferde ${_numberFormat.format(difference)} km artış girdiniz. '
          'Değer doğruysa kaydetmeye devam edebilirsiniz.',
          style: TextStyle(color: AppPalette.muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Tekrar kontrol et'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Color(0xFFFFB547),
              foregroundColor: Colors.black,
            ),
            child: Text('Değer doğru'),
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
    if (_difference < 0) return Color(0xFFFF586B);
    if (_difference > 20000) return Color(0xFFFFB547);
    return AppPalette.accent;
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
          constraints: BoxConstraints(maxWidth: 520),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppPalette.surfaceAlt, AppPalette.surface],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppPalette.accent.withValues(alpha: .20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .55),
                  blurRadius: 46,
                  offset: Offset(0, 22),
                ),
                BoxShadow(
                  color: AppPalette.accent.withValues(alpha: .045),
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
                            color: AppPalette.accent.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: AppPalette.accent.withValues(alpha: .18),
                            ),
                          ),
                          child: Icon(
                            Icons.speed_rounded,
                            color: AppPalette.accent,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AKILLI KM ASİSTANI',
                                style: TextStyle(
                                  color: AppPalette.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.15,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                vehicleName.isEmpty ? 'Kilometreyi güncelle' : vehicleName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppPalette.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.35,
                                ),
                              ),
                              if (plate.isNotEmpty) ...[
                                SizedBox(height: 2),
                                Text(
                                  plate,
                                  style: TextStyle(
                                    color: AppPalette.muted,
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
                          icon: Icon(Icons.close_rounded, color: AppPalette.muted),
                        ),
                      ],
                    ),
                    SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: AppPalette.text.withValues(alpha: .035),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppPalette.text.withValues(alpha: .07)),
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
                          SizedBox(width: 14),
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
                    SizedBox(height: 16),
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
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .2,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Güncel kilometre',
                        hintText: widget.currentKm.toString(),
                        prefixIcon: Icon(
                          Icons.pin_rounded,
                          color: AppPalette.accent,
                        ),
                        suffixText: 'KM',
                        suffixStyle: TextStyle(
                          color: AppPalette.accent,
                          fontWeight: FontWeight.w900,
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: .20),
                        labelStyle: TextStyle(color: AppPalette.muted),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(
                            color: AppPalette.text.withValues(alpha: .10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(
                            color: AppPalette.accent,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(color: Color(0xFFFF586B)),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide(color: Color(0xFFFF586B)),
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
                    SizedBox(height: 13),
                    Text(
                      'HIZLI ARTIŞ',
                      style: TextStyle(
                        color: AppPalette.subtle,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .9,
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [100, 250, 500, 1000, 5000]
                          .map((amount) => ActionChip(
                                onPressed: _isSaving
                                    ? null
                                    : () => _applyQuickIncrease(amount),
                                avatar: Icon(
                                  Icons.add_rounded,
                                  size: 15,
                                  color: AppPalette.accent,
                                ),
                                label: Text(
                                  '${_numberFormat.format(amount)} km',
                                  style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                backgroundColor: AppPalette.text.withValues(alpha: .04),
                                side: BorderSide(
                                  color: AppPalette.text.withValues(alpha: .08),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ))
                          .toList(),
                    ),
                    if (remainingToMaintenance != null) ...[
                      SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: (remainingToMaintenance <= 0
                                  ? Color(0xFFFF586B)
                                  : remainingToMaintenance <= 1000
                                      ? Color(0xFFFFB547)
                                      : AppPalette.accent)
                              .withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: (remainingToMaintenance <= 0
                                    ? Color(0xFFFF586B)
                                    : remainingToMaintenance <= 1000
                                        ? Color(0xFFFFB547)
                                        : AppPalette.accent)
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
                                  ? Color(0xFFFF586B)
                                  : remainingToMaintenance <= 1000
                                      ? Color(0xFFFFB547)
                                      : AppPalette.accent,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                remainingToMaintenance <= 0
                                    ? 'Bakım hedefi ${_numberFormat.format(remainingToMaintenance.abs())} km aşılmış görünüyor.'
                                    : 'Bakım hedefine yaklaşık ${_numberFormat.format(remainingToMaintenance)} km kaldı.',
                                style: TextStyle(
                                  color: AppPalette.muted,
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
                      SizedBox(height: 10),
                      Text(
                        'Bu artış normalden yüksek görünüyor. Kaydetmeden önce değeri kontrol edin.',
                        style: TextStyle(
                          color: Color(0xFFFFB547),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Color(0xFFFF586B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.accent,
                          foregroundColor: AppPalette.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _isSaving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _isSaving ? 'Kaydediliyor…' : 'Kilometreyi Güncelle',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    SizedBox(height: 6),
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                      child: Text('Vazgeç'),
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
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppPalette.subtle,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
          SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? AppPalette.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -.3,
            ),
          ),
        ],
      );
}
