# Dosya: android/app/proguard-rules.pro

# Flutter Çekirdek Kuralları
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# R8 ve Hata Ayıklama (Stacktrace / Line Number) Meta Verileri
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Signature
-renamesourcefileattribute SourceFile
-keep public class * extends java.lang.Exception

# Flutter Motoru & Play Core Eksik Sınıf Uyarılarını Engelleme (Hata Çözümü)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Pusher Channels & SLF4J Loglama Uyarılarını Engelleme (Hata Çözümü)
-dontwarn org.slf4j.**
-keep class com.pusher.** { *; }
-dontwarn com.pusher.**

# Firebase & Crashlytics
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# OneSignal Bildirim Servisi
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

# Google Play Hizmetleri, Konum ve Google Maps
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.baseflow.geolocator.** { *; }

# Desugaring ve Model Serileştirme
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**