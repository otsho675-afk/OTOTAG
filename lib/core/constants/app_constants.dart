import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // API ve Sunucu URL'leri
  static const String baseUrl = "https://eliteagency.sbs/api.php";
  static const String baseMediaUrl = "https://eliteagency.sbs/";
  static const String androidPackageName = 'com.oto.tag';
  static const String appleServiceId =
      String.fromEnvironment('APPLE_SERVICE_ID');
  static const String appleRedirectUri =
      String.fromEnvironment('APPLE_REDIRECT_URI');
  static const String googleWebClientId = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue:
          '73273804842-vq4fqlr07t8rhlgpituoka7nvnqltfba.apps.googleusercontent.com');

  // Üçüncü Parti Servis Anahtarları
  static const String pusherKey = "7197ebfa7d2e68b962dd";
  static String get googleMapsKey {
    const defined = String.fromEnvironment('MAPS_API_KEY');
    if (defined.isNotEmpty) return defined;
    return dotenv.isInitialized
        ? (dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '').trim()
        : '';
  }

  // ---------------------------------------------------------------------------
  // OTO TAG — Kurumsal tasarım sistemi
  // Mevcut ana renk değerleri korunur. Böylece eski ekranların davranışı ve
  // testleri bozulmadan yeni yüzeyler aynı marka diliyle kullanılabilir.
  // ---------------------------------------------------------------------------
  static const Color primaryColor = Color(0xFF00FFA3);
  static const Color primaryDeep = Color(0xFF00D68A);
  static const Color primaryDark = Color(0xFF009B69);
  static const Color primaryInk = Color(0xFF041A12);
  static const Color primarySoft = Color(0x1F00FFA3);

  static const Color dangerColor = Color(0xFFFF3366);
  static const Color warningColor = Color(0xFFF6B73C);
  static const Color infoColor = Color(0xFF6FA8FF);

  static const Color bgColor = Color(0xFF030305);
  static const Color bgElevated = Color(0xFF08090C);
  static const Color cardColor = Color(0xFF111115);
  static const Color cardElevated = Color(0xFF15161B);
  static const Color fieldColor = Color(0xFF191D22);
  static const Color fieldHoverColor = Color(0xFF1E232A);

  static const Color textColor = Color(0xFFF5F7F8);
  static const Color mutedColor = Color(0xFF939AA4);
  static const Color subtleTextColor = Color(0xFF737B86);
  static const Color borderColor = Color(0xFF292E35);
  static const Color borderStrongColor = Color(0xFF353C45);

  static const LinearGradient premiumSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF17191F), Color(0xFF0E1014)],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, primaryDeep],
  );
}
