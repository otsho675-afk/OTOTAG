// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import '../core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import 'rental_market_style.dart';

Future<String?> showRentalAccountMenu(BuildContext context) =>
    showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppPalette.surface,
        constraints: BoxConstraints(maxWidth: 520),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: rentalBorder,
                                  borderRadius: BorderRadius.circular(4)))),
                      SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: Text('Firma menüsü',
                                style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700))),
                        IconButton(
                            tooltip: 'Menüyü kapat',
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close_rounded))
                      ]),
                      SizedBox(height: 8),
                      for (final item in [
                        (
                          'profile',
                          Icons.storefront_outlined,
                          'Firma hesabım',
                          'Bilgiler, teslim konumu ve değerlendirmeler'
                        ),
                        (
                          'subscription',
                          Icons.workspace_premium_outlined,
                          'Abonelik ve ödeme',
                          'Aylık üyelik, satın alımları geri yükleme'
                        ),
                        (
                          'diagnostic',
                          Icons.car_repair_outlined,
                          'Araç arıza tespit',
                          'Kod sözlüğü ve canlı OBD • Üyeliğe dahil'
                        ),
                        (
                          'reputation',
                          Icons.star_outline_rounded,
                          'Müşteride görünen profil',
                          'Yıldızlar, rozetler ve tüm müşteri yorumları'
                        ),
                        (
                          'history',
                          Icons.history_rounded,
                          'Kiralama geçmişi',
                          'Tamamlanan işler ve anlaşmazlık bildirimi'
                        ),
                        (
                          'refresh',
                          Icons.refresh_rounded,
                          'Listeyi yenile',
                          'Araç ve teklif durumlarını güncelle'
                        ),
                      ])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              tileColor: AppPalette.field,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: rentalBorder)),
                              leading: Icon(item.$2,
                                  color: AppPalette.accent, size: 24),
                              title: Text(item.$3,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(item.$4,
                                  style: TextStyle(
                                      color: rentalMuted,
                                      fontSize: 12,
                                      height: 1.5)),
                              trailing: Icon(Icons.chevron_right,
                                  size: 20, color: rentalMuted),
                              onTap: () => Navigator.pop(context, item.$1),
                            )),
                    ]))));
