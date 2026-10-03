import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../services/rental_service.dart';
import 'rental_market_style.dart';

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
    final name = bid[company ? 'customer_name' : 'company_name'] ?? '';
    final amount = rentalCents('${bid['amount']}');
    final daily = rentalCents('${bid['quoted_daily_price']}');
    final statusLabel = status == 'accepted'
        ? 'Eşleşti'
        : status == 'completed'
            ? 'Tamamlandı'
            : status == 'pending'
                ? (ownTurn ? 'Yanıtın bekleniyor' : 'Yanıt bekleniyor')
                : 'Kapandı';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          border: Border.all(
              color: status == 'accepted'
                  ? AppConstants.primaryColor
                  : rentalBorder),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text('${bid['car_brand_model'] ?? 'Kiralık araç'}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: RentalTag(statusLabel,
                  accent: status == 'accepted' || ownTurn)),
        ]),
        const SizedBox(height: 6),
        Text('$name', style: const TextStyle(color: rentalMuted, fontSize: 13)),
        const SizedBox(height: 18),
        const Text('SON TEKLİF',
            style: TextStyle(
                color: rentalMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 5),
        Text(amount == null ? '—' : '${rentalPrice(amount)} ₺',
            style: const TextStyle(
                color: AppConstants.primaryColor,
                fontSize: 28,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          RentalTag('${bid['rent_days']} gün',
              icon: Icons.calendar_today_outlined),
          if (daily != null) RentalTag('İlan: ${rentalPrice(daily)} ₺ / gün'),
        ]),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: rentalBorder)),
        if (status == 'pending') ...[
          Text(
              ownTurn
                  ? 'Karşı tarafın teklifini değerlendirin.'
                  : 'Karşı tarafın yanıtı bekleniyor.',
              style: const TextStyle(
                  color: rentalMuted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (ownTurn) ...[
              FilledButton(
                  onPressed:
                      busy ? null : () => onAction('accept_rentacar_bid', bid),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: Colors.black),
                  child: const Text('Kabul et')),
              OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.primaryColor),
                  onPressed:
                      busy ? null : () => onAction('counter_rentacar_bid', bid),
                  child: const Text('Karşı teklif')),
            ],
            if (company)
              TextButton(
                  onPressed:
                      busy ? null : () => onAction('reject_rentacar_bid', bid),
                  child: const Text('Reddet',
                      style: const TextStyle(color: Colors.white70))),
          ]),
        ] else if (status == 'accepted')
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.black),
                onPressed: busy ? null : (onBooking ?? onChat),
                child: Text(
                    onBooking == null ? 'Mesajlaş' : 'Rezervasyon detayı')),
            if (onBooking != null)
              TextButton(
                  onPressed: busy ? null : onChat,
                  child: const Text('Mesajlaş')),
            if (company)
              OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.primaryColor),
                  onPressed: busy
                      ? null
                      : () => onAction('complete_rentacar_booking', bid),
                  child: const Text('Kiralamayı tamamla')),
          ])
        else ...[
          if ((status == 'completed' || status == 'cancelled') &&
              onBooking != null)
            TextButton(
                onPressed: onBooking, child: const Text('Rezervasyon detayı')),
          Text(
              status == 'completed'
                  ? 'Kiralama tamamlandı.'
                  : status == 'cancelled'
                      ? 'Rezervasyon yönetici tarafından iptal edildi.'
                      : 'Teklif kapatıldı.',
              style: const TextStyle(color: Colors.white60)),
        ],
        if (!company && status != 'accepted')
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed:
                      busy ? null : () => onAction('delete_rentacar_bid', bid),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Teklifi sil'))),
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
            backgroundColor: AppConstants.cardColor,
            title: const Text('Karşı teklif',
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          '${bid['rent_days']} günlük kiralamanın toplam ücretini girin.',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                              labelText: 'Toplam ücret (₺)',
                              labelStyle: TextStyle(color: Colors.white70)),
                          validator: (value) => rentalCents(value ?? '') == null
                              ? 'Pozitif bir ücret girin (en fazla 2 ondalık).'
                              : null),
                    ]))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: Colors.black),
                  onPressed: () {
                    if (form.currentState!.validate())
                      Navigator.pop(ctx, controller.text.trim());
                  },
                  child: const Text('Teklif gönder'))
            ],
          )));
  // Let the dialog's closing animation release its text field first.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}
