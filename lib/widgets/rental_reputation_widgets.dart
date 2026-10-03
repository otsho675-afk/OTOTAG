import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../services/rental_service.dart';
import 'rental_market_style.dart';

class RentalReputationSummary extends StatelessWidget {
  const RentalReputationSummary({super.key, required this.reputation});
  final Map<String, dynamic> reputation;
  @override
  Widget build(BuildContext context) {
    final count = rentalId(reputation['review_count']);
    final average = double.tryParse('${reputation['average']}');
    final badge = reputation['badge'] as Map?;
    final color = badge?['id'] == 'gold'
        ? const Color(0xFFFFD071)
        : badge?['id'] == 'silver'
            ? const Color(0xFFC6D6E3)
            : const Color(0xFFDCA480);
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppConstants.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: rentalBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                    average == null || count == 0
                        ? 'Henüz puan yok'
                        : '${average.toStringAsFixed(2).replaceAll('.', ',')} / 5',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)),
                if (badge != null)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: color.withValues(alpha: .4))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.workspace_premium_outlined,
                            color: color, size: 22),
                        const SizedBox(width: 6),
                        Flexible(
                            child: Text('${badge['title']}',
                                style: TextStyle(
                                    color: color, fontWeight: FontWeight.bold)))
                      ])),
              ]),
          const SizedBox(height: 10),
          RentalRatingStars(rating: count > 0 ? average ?? 0 : 0, size: 30),
          const SizedBox(height: 10),
          Text(
              '$count değerlendirme • ${rentalId(reputation['unique_customers'])} farklı müşteri',
              style: const TextStyle(color: rentalMuted, height: 1.5)),
          const SizedBox(height: 10),
          Text(
              badge == null
                  ? 'Rozet için yeterli müşteri ve puan henüz oluşmadı.'
                  : 'Rozet puanı: ${reputation['badge_score']} / 5',
              style: const TextStyle(
                  color: rentalMuted, fontSize: 12, height: 1.5)),
          TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  constraints: const BoxConstraints(maxWidth: 640),
                  builder: (_) => Theme(
                      data: rentalTheme(),
                      child: const SafeArea(
                          child: SingleChildScrollView(
                              padding: EdgeInsets.all(24),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Rozetler nasıl kazanılır?',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold)),
                                    SizedBox(height: 16),
                                    Text(
                                        'Yalnızca tamamlanmış kiralamaların müşterileri puan verebilir. Her kiralamaya tek değerlendirme bırakılır. Yorum yazmak isteğe bağlıdır.',
                                        style: TextStyle(
                                            color: rentalMuted, height: 1.6)),
                                    SizedBox(height: 16),
                                    Text(
                                        'Bronz: en az 5 farklı müşteri, rozet puanı ≥ 3,80\nGümüş: en az 10 farklı müşteri, rozet puanı ≥ 4,20\nAltın: en az 20 farklı müşteri, rozet puanı ≥ 4,50',
                                        style: TextStyle(
                                            color: Colors.white, height: 1.8)),
                                    SizedBox(height: 16),
                                    Text(
                                        'Profil ortalaması tüm kiralama puanlarını gösterir. Rozet puanında her müşterinin kendi ortalaması eşit ağırlık taşır; aynı müşterinin çok sayıda kiralaması avantaj sağlamaz. Az değerlendirmeyle yüksek rozet alınmaması için hesaba 5 adet 3 yıldızlık başlangıç ağırlığı eklenir.\n\nRozet puanı = (müşteri ortalamalarının toplamı + 15) / (farklı müşteri sayısı + 5). Karar yuvarlanmamış puandan verilir. Puan düştüğünde rozet de düşebilir. Ücretli üyelik rozet kazandırmaz.',
                                        style: TextStyle(
                                            color: rentalMuted, height: 1.6)),
                                  ]))))),
              icon: const Icon(Icons.info_outline, size: 17),
              label: const Text('Rozet kuralları')),
        ]));
  }
}

class RentalRatingStars extends StatelessWidget {
  const RentalRatingStars({super.key, required this.rating, this.size = 20});
  final double rating, size;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '${rating.toStringAsFixed(2)} / 5 yıldız',
      child: Wrap(
          spacing: 3,
          children: List.generate(5, (i) {
            final fraction = (rating - i).clamp(0.0, 1.0);
            return Stack(children: [
              Icon(Icons.star_rounded, color: rentalBorder, size: size),
              ClipRect(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: Icon(Icons.star_rounded,
                          color: const Color(0xFFFFD071), size: size))),
            ]);
          })));
}

class RentalReviewCard extends StatelessWidget {
  const RentalReviewCard({super.key, required this.review});
  final Map<String, dynamic> review;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: rentalBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${review['reviewer_name'] ?? 'Müşteri'}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      5,
                      (i) => Icon(
                          i < rentalId(review['rating'])
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFFFD071),
                          size: 20))),
            ]),
        const SizedBox(height: 8),
        const RentalTag('Tamamlanmış kiralama',
            icon: Icons.verified_outlined, accent: true),
        if ('${review['comment'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('${review['comment']}',
              style: const TextStyle(color: Colors.white70, height: 1.6))
        ],
        const SizedBox(height: 10),
        Text('${review['created_at'] ?? ''}'.split(' ').first,
            style: const TextStyle(color: rentalMuted, fontSize: 11)),
      ]));
}
