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

  // Proje Geneli Ana Renkler
  static const Color primaryColor =
      Color(0xFF00FFA3); // neonGreen / _primaryColor
  static const Color dangerColor = Color(0xFFFF3366); // alertRed / _dangerColor
  static const Color bgColor = Color(0xFF030305); // pureBlack / _bgColor
  static const Color cardColor = Color(0xFF111115); // panelBlack / _cardColor
  static const Color mutedColor = Color(0xFF939AA4);
  static const Color fieldColor = Color(0xFF191D22);
  static const Color borderColor = Color(0xFF292E35);
}
