# OTO TAG Product Growth Suite

Bu branch, mevcut eşleşme ve davet sisteminin üzerine ürün büyüme özelliklerini ekler.

## Eklenen özellikler

- İlk açılış onboarding
- OTO TAG Puan mağazası
- Opsiyonel SMS telefon doğrulaması
- OTO TAG doğrulanmış sağlayıcı rozeti
- Mesafe/hizmet/saat bazlı akıllı fiyat önerisi
- Canlı eşleşme tarama bilgisi
- Sağlayıcı performans metrikleri
- Favori sağlayıcı
- Acil yol yardım modu
- Araç sağlık merkezi
- Araç tarihi/bakım push hatırlatmaları
- Admin 30 günlük büyüme analitiği

## SMS ayarı

SMS doğrulama varsayılan olarak kapalıdır. SMS sağlayıcısı bağlanana kadar mevcut kayıt akışı çalışmaya devam eder.

Sunucu .env dosyasına aşağıdakiler eklenebilir:

    SMS_VERIFICATION_REQUIRED=0
    SMS_HTTP_URL=
    SMS_HTTP_TOKEN=
    SMS_HTTP_SENDER=OTO TAG

SMS sağlayıcısı hazır olduğunda SMS_VERIFICATION_REQUIRED=1 yapılır.

SMS_HTTP_URL adresine OTO TAG JSON gövdesiyle POST gönderir: to, message ve sender alanları.
Token varsa Authorization: Bearer <SMS_HTTP_TOKEN> headerı gönderilir.

SMS sağlayıcısının API formatı farklıysa yalnızca growthSendSms() adaptörü değiştirilmelidir.

## Puan kataloğu

- 100 Puan → 7 Gün Premium
- 250 Puan → 30 Gün Premium
- 300 Puan → 30 Gün OBD
- 500 Puan → 15 Gün işletme üyeliği (usta / rent a car)

## Otomatik veritabanı migrasyonları

growth_features.php gerekli kolon ve tabloları otomatik oluşturur:

- users.is_verified
- users.phone_verified_at
- users.last_active_at
- jobs.is_emergency
- jobs.prefer_favorites
- phone_verifications
- favorite_providers
- reward_redemptions
- growth_reminder_log

Mevcut referral migrasyonları ayrıca korunur.

## Güvenlik

- OTP kodu veritabanında düz metin tutulmaz.
- Kod 5 dakika geçerlidir.
- Maksimum hatalı kod denemesi sınırlandırılmıştır.
- Doğrulanmış kayıt tokenı 30 dakika geçerlidir.
- Puan harcama işlemleri DB transaction ile yapılır.
- Aynı davet ödülü bir kez verilir.
- Tahmini eşleşmeler referral ödülü üretmez.