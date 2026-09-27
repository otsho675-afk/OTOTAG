import 'package:flutter/material.dart';

class AppConstants {
  // API ve Sunucu URL'leri
  static const String baseUrl = "https://eliteagency.sbs/api.php";
  static const String baseMediaUrl = "https://eliteagency.sbs/";
  
  // Üçüncü Parti Servis Anahtarları
  static const String pusherKey = "7197ebfa7d2e68b962dd";
  static const String googleMapsKey = "AIzaSyA_NvuYHjKyG7O0ZDYJLvxfgClvdHlMlJU";
  
  // Proje Geneli Ana Renkler
  static const Color primaryColor = Color(0xFF00FFA3); // neonGreen / _primaryColor
  static const Color dangerColor = Color(0xFFFF3366);  // alertRed / _dangerColor
  static const Color bgColor = Color(0xFF030305);      // pureBlack / _bgColor
  static const Color cardColor = Color(0xFF111115);    // panelBlack / _cardColor
}