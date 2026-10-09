// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import '../core/theme/app_palette.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../services/rental_service.dart';
import 'rental_market_style.dart';
import '../core/theme/app_motion.dart';

class RentalBidCard extends StatelessWidget {
  const RentalBidCard(
      {super.key,
      required this.bid,
      required this.company,
      required this.busy,
      required this.onAction,
      required this.onChat,
      this.onBooking});
  final Map<String, dynamic> bid;
  final bool company;
  final bool busy;
  final Future<void> Function(String, Map<String, dynamic>) onAction;
  final VoidCallback onChat;
  final VoidCallback? onBooking;

  @override
  Widget build(BuildContext context) {
    final status = bid['status'];
    final ownTurn = bid['last_offer_by'] == (company ? 'customer' : 'company');
    final agreed =
        bid['agreement_at'] != null && '${bid['agreement_at']}'.isNotEmpty;
    final name = bid[company ? 'customer_name' : 'company_name'] ?? '';
    final amount = rentalCents('${bid['amount']}');
    final daily = rentalCents('${bid['quoted_daily_price']}');
    final statusLabel = status == 'accepted'
        ? (agreed ? 'Anlaşıldı' : 'Görüşme')
        : status == 'completed'
            ? 'Tamamlandı'
            : status == 'pending'
                ? (ownTurn ? 'Yanıtın bekleniyor' : 'Yanıt bekleniyor')
                : 'Kapandı';
    return AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.entrance),
      curve: AppMotion.curve,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppPalette.surface,
          border: Border.all(
              color: status == 'accepted'
                  ? AppPalette.accent
                  : rentalBorder),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text('${bid['car_brand_model'] ?? 'Kiralık araç'}',
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w700))),
          SizedBox(width: 8),
          ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 130),
              child: RentalTag(statusLabel,
                  accent: status == 'accepted' || ownTurn)),
        ]),
        SizedBox(height: 6),
        Text('$name', style: TextStyle(color: rentalMuted, fontSize: 13)),
        SizedBox(height: 18),
        Text('SON TEKLİF',
            style: TextStyle(
                color: rentalMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        SizedBox(height: 5),
        Text(amount == null ? '—' : '${rentalPrice(amount)} ₺',
            style: TextStyle(
                color: AppPalette.accent,
                fontSize: 28,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          RentalTag('${bid['rent_days']} gün',
              icon: Icons.calendar_today_outlined),
          if (daily != null) RentalTag('İlan: ${rentalPrice(daily)} ₺ / gün'),
        ]),
        Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: rentalBorder)),
        if (status == 'pending') ...[
          Text(
              ownTurn
                  ? 'Karşı tarafın teklifini değerlendirin.'
                  : 'Karşı tarafın yanıtı bekleniyor.',
              style: TextStyle(
                  color: rentalMuted, fontSize: 12, height: 1.5)),
          SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (ownTurn) ...[
              FilledButton(
                  onPressed:
                      busy ? null : () => onAction('accept_rentacar_bid', bid),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.accent,
                      foregroundColor: Colors.black),
                  child: Text('Kabul et')),
              OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.accent),
                  onPressed:
                      busy ? null : () => onAction('counter_rentacar_bid', bid),
                  child: Text('Karşı teklif')),
            ],
            if (company)
              TextButton(
                  onPressed:
                      busy ? null : () => onAction('reject_rentacar_bid', bid),
                  child: Text('Reddet',
                      style: TextStyle(color: AppPalette.muted))),
          ]),
        ] else if (status == 'accepted')
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.accent,
                    foregroundColor: Colors.black),
                onPressed: busy ? null : (onBooking ?? onChat),
                child: Text(
                    onBooking == null ? 'Mesajlaş' : 'Rezervasyon detayı')),
            if (onBooking != null)
              TextButton(
                  onPressed: busy ? null : onChat,
                  child: Text('Mesajlaş')),
            if (company)
              OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.accent),
                  onPressed: busy
                      ? null
                      : () => onAction(
                          agreed
                              ? 'complete_rentacar_booking'
                              : 'agree_rentacar_booking',
                          bid),
                  child: Text(agreed ? 'İşi tamamla' : 'Anlaştık')),
          ])
        else ...[
          if ((status == 'completed' || status == 'cancelled') &&
              onBooking != null)
            TextButton(
                onPressed: onBooking, child: Text('Rezervasyon detayı')),
          Text(
              status == 'completed'
                  ? 'Kiralama tamamlandı.'
                  : status == 'cancelled'
                      ? 'Rezervasyon yönetici tarafından iptal edildi.'
                      : 'Teklif kapatıldı.',
              style: TextStyle(color: AppPalette.muted)),
        ],
        if (!company && status != 'accepted')
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed:
                      busy ? null : () => onAction('delete_rentacar_bid', bid),
                  icon: Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Teklifi sil'))),
      ]),
    );
  }
}

Future<String?> showRentalCounterDialog(
    BuildContext context, Map<String, dynamic> bid) async {
  final controller = TextEditingController(text: bid['amount'].toString());
  final form = GlobalKey<FormState>();
  final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Theme(
          data: rentalTheme(),
          child: AlertDialog(
            backgroundColor: AppPalette.surface,
            title: Text('Karşı teklif',
                style: TextStyle(color: AppPalette.text)),
            content: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          '${bid['rent_days']} günlük kiralamanın toplam ücretini girin.',
                          style: TextStyle(color: AppPalette.muted)),
                      SizedBox(height: 12),
                      TextFormField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(color: AppPalette.text),
                          decoration: InputDecoration(
                              labelText: 'Toplam ücret (₺)',
                              labelStyle: TextStyle(color: AppPalette.muted)),
                          validator: (value) => rentalCents(value ?? '') == null
                              ? 'Pozitif bir ücret girin (en fazla 2 ondalık).'
                              : null),
                    ]))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Vazgeç')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.accent,
                      foregroundColor: Colors.black),
                  onPressed: () {
                    if (form.currentState!.validate()) {
                      Navigator.pop(ctx, controller.text.trim());
                    }
                  },
                  child: Text('Teklif gönder'))
            ],
          )));
  // Let the dialog's closing animation release its text field first.
  await Future<void>.delayed(Duration(milliseconds: 300));
  controller.dispose();
  return result;
}
