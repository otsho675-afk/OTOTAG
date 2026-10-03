import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/rental_service.dart';

const rentalMuted = AppConstants.mutedColor;
const rentalField = AppConstants.fieldColor;
const rentalBorder = AppConstants.borderColor;

ThemeData rentalTheme() => appTheme();

class RentalTag extends StatelessWidget {
  const RentalTag(this.text, {super.key, this.icon, this.accent = false});
  final String text;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: accent ? const Color(0xFF0C2B20) : rentalField,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: accent ? const Color(0xFF164B37) : rentalBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 13,
                color: accent ? AppConstants.primaryColor : rentalMuted),
            const SizedBox(width: 5),
          ],
          Flexible(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent
                          ? AppConstants.primaryColor
                          : const Color(0xFFD1D6DC)))),
        ]),
      );
}

class RentalVehicleMedia extends StatelessWidget {
  const RentalVehicleMedia(
      {super.key,
      required this.photo,
      this.label = 'Kiralık',
      this.available = true,
      this.compact = false});
  final String photo, label;
  final bool available;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo.trim().isNotEmpty && photo != 'null';
    final url = Uri.parse(AppConstants.baseMediaUrl).resolve(photo).toString();
    Widget placeholder() => const Center(
        child: Icon(Icons.directions_car_filled_rounded,
            color: rentalMuted, size: 44));
    return Container(
        height: compact
            ? 82
            : hasPhoto
                ? 148
                : 100,
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF20292C), Color(0xFF15191E)])),
        child: Stack(fit: StackFit.expand, children: [
          Padding(
              padding: compact
                  ? const EdgeInsets.all(6)
                  : const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: hasPhoto
                  ? Image.network(url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => placeholder(),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : placeholder())
                  : placeholder()),
          if (!compact)
            Positioned(
                top: 10,
                left: 12,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xEC11171B),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle,
                          size: 6,
                          color: available
                              ? AppConstants.primaryColor
                              : rentalMuted),
                      const SizedBox(width: 6),
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ]))),
        ]));
  }
}

class RentalListingCard extends StatelessWidget {
  const RentalListingCard(
      {super.key,
      required this.car,
      required this.days,
      required this.pending,
      required this.busy,
      required this.onRequest,
      this.totalBudget,
      this.compact = false,
      this.onCompanyProfile,
      this.onNegotiate});
  final Map<String, dynamic> car;
  final int? days;
  final int? totalBudget;
  final bool pending, busy;
  final bool compact;
  final VoidCallback onRequest;
  final VoidCallback? onNegotiate;
  final VoidCallback? onCompanyProfile;

  @override
  Widget build(BuildContext context) {
    final photo = '${car['photo1'] ?? car['photo'] ?? ''}'.trim();
    final daily = rentalCents('${car['daily_price']}');
    final validDays = days != null && days! >= 1 && days! <= 365;
    final total = daily != null && validDays ? daily * days! : null;
    final description = '${car['description'] ?? ''}'.trim();
    final year = '${car['model_year'] ?? ''}'.trim();
    if (compact) {
      return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppConstants.cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: rentalBorder)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(
                  width: 74,
                  height: 74,
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: RentalVehicleMedia(photo: photo, compact: true))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${car['car_brand_model'] ?? 'Kiralık araç'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        '${car['city'] ?? ''}${year.isNotEmpty && year != 'null' ? ' • $year' : ''}',
                        style:
                            const TextStyle(color: rentalMuted, fontSize: 12)),
                    if (rentalId(car['company_review_count']) > 0)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            const Icon(Icons.star_rounded,
                                color: Color(0xFFFFD071), size: 17),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(
                                    '${car['company_rating']} • ${car['company_review_count']} değerlendirme',
                                    style: const TextStyle(
                                        color: rentalMuted, fontSize: 11))),
                          ])),
                  ])),
            ]),
            const SizedBox(height: 4),
            TextButton.icon(
                onPressed: onCompanyProfile,
                style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36)),
                icon: const Icon(Icons.storefront_outlined, size: 17),
                label: Text('${car['company_name'] ?? 'Firma profili'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (description.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: rentalMuted, fontSize: 12))),
            const Divider(height: 1, color: rentalBorder),
            const SizedBox(height: 12),
            Text(
                total == null
                    ? (daily == null ? '—' : '${rentalPrice(daily)} ₺ / gün')
                    : '${rentalPrice(total)} ₺',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                total == null
                    ? 'Kiralama için geçerli bir süre seçin.'
                    : '$days gün toplam • ${rentalPrice(daily!)} ₺ / gün',
                style: const TextStyle(
                    color: rentalMuted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: busy ||
                        pending ||
                        total == null ||
                        (totalBudget != null && total > totalBudget!)
                    ? null
                    : onRequest,
                child: Text(
                    pending
                        ? 'Teklifiniz mevcut'
                        : totalBudget == null
                            ? 'Bütçeyi belirle'
                            : 'Teklif ver',
                    textAlign: TextAlign.center)),
            if (onNegotiate != null && totalBudget != null && !pending)
              TextButton(
                  onPressed: busy || total == null || total > totalBudget!
                      ? null
                      : onNegotiate,
                  child: const Text('Pazarlık için teklif gönder',
                      textAlign: TextAlign.center)),
          ]));
    }
    return Container(
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: rentalBorder)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!compact) RentalVehicleMedia(photo: photo),
        Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                if (compact) ...[
                  SizedBox(
                      width: 82,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child:
                              RentalVehicleMedia(photo: photo, compact: true))),
                  const SizedBox(width: 14),
                ],
                Expanded(
                    child: Text('${car['car_brand_model'] ?? 'Kiralık araç'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -.3))),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                RentalTag('${car['city'] ?? ''}',
                    icon: Icons.location_on_outlined),
                if (year.isNotEmpty && year != 'null')
                  RentalTag(year, icon: Icons.calendar_today_outlined),
                if (rentalId(car['company_review_count']) > 0)
                  RentalTag(
                      '${car['company_rating']} (${car['company_review_count']})',
                      icon: Icons.star_rounded),
              ]),
              if (description.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: rentalMuted, fontSize: 12, height: 1.5))),
              Tooltip(
                  message: 'Firma profili, puan ve yorumlar',
                  child: InkWell(
                      onTap: onCompanyProfile,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            const Icon(Icons.storefront_outlined,
                                size: 16, color: rentalMuted),
                            const SizedBox(width: 7),
                            Expanded(
                                child: Text('${car['company_name'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFFCFD4DA),
                                        fontSize: 12))),
                            if (onCompanyProfile != null)
                              const Icon(Icons.chevron_right,
                                  color: rentalMuted, size: 18),
                          ])))),
              const Divider(height: 1, color: rentalBorder),
              const SizedBox(height: 14),
              Text(
                  total == null
                      ? (daily == null ? '—' : '${rentalPrice(daily)} ₺ / gün')
                      : '${rentalPrice(total)} ₺',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 23,
                      letterSpacing: -.5)),
              const SizedBox(height: 4),
              Text(
                  total == null
                      ? 'Kiralama için geçerli bir süre seçin.'
                      : '$days gün toplam • ${rentalPrice(daily!)} ₺ / gün',
                  style: const TextStyle(
                      color: rentalMuted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 14),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: busy ||
                              pending ||
                              total == null ||
                              (totalBudget != null && total > totalBudget!)
                          ? null
                          : onRequest,
                      child: Text(
                          pending
                              ? 'Teklifiniz mevcut'
                              : totalBudget == null
                                  ? 'Bütçeyi belirle'
                                  : 'Teklif ver',
                          textAlign: TextAlign.center))),
              if (onNegotiate != null && totalBudget != null && !pending)
                SizedBox(
                    width: double.infinity,
                    child: TextButton(
                        onPressed: busy || total == null || total > totalBudget!
                            ? null
                            : onNegotiate,
                        child: const Text('Pazarlık için teklif gönder',
                            textAlign: TextAlign.center))),
            ])),
      ]),
    );
  }
}
