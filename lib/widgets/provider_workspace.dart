import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_motion.dart';

class ProviderStatusHeader extends StatelessWidget {
  const ProviderStatusHeader(
      {super.key,
      required this.service,
      required this.online,
      required this.jobCount,
      required this.radius,
      required this.onToggle,
      required this.onRefresh});
  final String service;
  final bool online;
  final int jobCount;
  final double radius;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppConstants.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.engineering_outlined,
                  color: AppConstants.primaryColor)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(service,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 3),
                Text(online ? 'İş almaya açıksın' : 'Şu an çevrimdışısın',
                    style: const TextStyle(
                        color: AppConstants.mutedColor, fontSize: 12))
              ])),
          Switch.adaptive(
              value: online,
              onChanged: onToggle,
              activeTrackColor: AppConstants.primaryColor,
              activeThumbColor: Colors.black),
        ]),
        if (online) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.near_me_outlined,
                size: 16, color: AppConstants.primaryColor),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    '$jobCount uygun talep • ${radius.toStringAsFixed(0)} km alan',
                    style: const TextStyle(
                        color: AppConstants.mutedColor, fontSize: 12))),
            IconButton(
                tooltip: 'Talepleri yenile',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 20))
          ])
        ],
      ]));
}

class ProviderNavigationBar extends StatelessWidget {
  const ProviderNavigationBar(
      {super.key, required this.onSelect, this.selected = 0});
  final ValueChanged<int> onSelect;
  final int selected;
  @override
  Widget build(BuildContext context) => Container(
      decoration: const BoxDecoration(
          color: AppConstants.cardColor,
          border: Border(top: BorderSide(color: AppConstants.borderColor))),
      child: SafeArea(
          top: false,
          child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Row(children: [
                    _item(0, Icons.map_outlined, 'Harita'),
                    _item(1, Icons.history_rounded, 'İşler'),
                    _item(2, Icons.account_balance_wallet_outlined, 'Kazanç'),
                    _item(4, Icons.person_outline_rounded, 'Hesap'),
                    _item(6, Icons.more_horiz_rounded, 'Diğer'),
                  ])))));
  Widget _item(int id, IconData icon, String label) => Expanded(
      child: Semantics(
          selected: selected == id,
          button: true,
          child: AppInteractiveSurface(
              onTap: () => onSelect(id),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon,
                        size: 23,
                        color: selected == id
                            ? AppConstants.primaryColor
                            : AppConstants.mutedColor),
                    const SizedBox(height: 4),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: selected == id
                                ? AppConstants.primaryColor
                                : AppConstants.mutedColor,
                            fontSize: 11))
                  ])))));
}

class ProviderOfflineDashboard extends StatelessWidget {
  const ProviderOfflineDashboard(
      {super.key,
      required this.service,
      required this.rating,
      required this.reviewCount,
      required this.monthlyEarnings,
      required this.onOnline,
      required this.onSubscription,
      required this.onHistory});
  final String service;
  final double rating, monthlyEarnings;
  final int reviewCount;
  final VoidCallback onOnline, onSubscription, onHistory;
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Usta paneli',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('$service • İşlerini buradan yönet',
                            style: const TextStyle(
                                color: AppConstants.mutedColor)),
                        const SizedBox(height: 24),
                        IntrinsicHeight(
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              Expanded(
                                  child: _stat(
                                      Icons.account_balance_wallet_outlined,
                                      'Bu ay',
                                      NumberFormat.currency(
                                              locale: 'tr_TR',
                                              symbol: '₺',
                                              decimalDigits: 2)
                                          .format(monthlyEarnings))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _stat(
                                      Icons.star_outline_rounded,
                                      'Değerlendirme',
                                      reviewCount == 0
                                          ? 'Henüz puan yok'
                                          : '${rating.toStringAsFixed(1)} • $reviewCount yorum')),
                            ])),
                        const SizedBox(height: 20),
                        Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                color: AppConstants.cardColor,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: AppConstants.borderColor)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      color: AppConstants.primaryColor,
                                      size: 36),
                                  const SizedBox(height: 16),
                                  const Text('Hazır olduğunda çevrimiçi ol',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Konumuna ve hizmetine uygun talepleri gör. Fiyatını teklif et, anlaşınca müşteriye doğru yola çık.',
                                      style: TextStyle(
                                          color: AppConstants.mutedColor,
                                          height: 1.6)),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                          onPressed: onOnline,
                                          style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  AppConstants.primaryColor,
                                              foregroundColor: Colors.black,
                                              minimumSize:
                                                  const Size.fromHeight(52)),
                                          icon: const Icon(
                                              Icons.power_settings_new_rounded),
                                          label: const Text('Çevrimiçi ol'))),
                                ])),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                            onPressed: onHistory,
                            icon: const Icon(Icons.history_rounded),
                            label: const Text('Geçmiş işlerim')),
                        TextButton(
                            onPressed: onSubscription,
                            child: const Text('Üyelik ve ödeme')),
                      ])))));
  Widget _stat(IconData icon, String title, String value) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppConstants.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppConstants.primaryColor),
        const SizedBox(height: 14),
        Text(title,
            style:
                const TextStyle(color: AppConstants.mutedColor, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))
      ]));
}

class ProviderJobPreview extends StatelessWidget {
  const ProviderJobPreview(
      {super.key,
      required this.service,
      required this.customer,
      required this.description,
      required this.distance,
      required this.onOffer});
  final String service, customer, description, distance;
  final VoidCallback onOffer;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppConstants.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(service,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Text('$distance km',
              style: const TextStyle(
                  color: AppConstants.primaryColor, fontSize: 12))
        ]),
        const SizedBox(height: 6),
        Text(customer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: AppConstants.mutedColor, fontSize: 12)),
        const SizedBox(height: 6),
        Expanded(
            child: Text(
                description.isEmpty
                    ? 'Müşterinin talebini incele ve teklifini ilet.'
                    : description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppConstants.mutedColor, height: 1.4))),
        const SizedBox(height: 8),
        SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: onOffer,
                style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.black),
                child: const Text('Talebi incele ve teklif ver'))),
      ]));
}
