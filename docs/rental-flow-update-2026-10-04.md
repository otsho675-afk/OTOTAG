# Rent a Car eşleşme güncellemesi — 4 Ekim 2026

## Kurulum

1. Sunucudaki mevcut dosyaları ve veritabanını yedekle.
2. `build/rental-matching-backend-2026-10-04.zip` içindeki `rentacar_api.php` ve `rental_reputation.php` dosyalarını `/www/wwwroot/eliteagency.sbs/` klasörüne, mevcut `api.php` ile aynı yere yükle. Aynı adlı dosyaların üzerine yaz. `.env` dosyasını değiştirme.
3. Bu paket mevcut güncel OTOTAG backend üzerine uygulanır. Yalnızca `api.php` yüklemek bu değişikliği kurmaz. İlk kiralama API çağrısında `rentacar_bids.agreement_at` alanı otomatik eklenir; sunucudaki veritabanı kullanıcısının ALTER yetkisi gerekir. Ayrı SQL yüklemesi yoktur.
4. Flutter kaynakları bu projede güncellendi. Android için proje terminalinde `flutter build appbundle --release` çalıştır. iPhone için güncel kaynakları Codemagic ile yeniden derleyip TestFlight sürümünü güncelle. Eski uygulamayı silip aynı derlemeyi yüklemek yeni ekranları getirmez.

## Yeni uygulamadaki akış

- Müşteri toplam bütçe ve gün sayısı belirler. Bütçe penceresi kaydedildiğinde şehirdeki uygun araçlar otomatik sorgulanır.
- Teklif ver → onay penceresi → firmaya bekleyen teklif. İlk teklif tutarı ilandaki günlük ücret × gün sayısıdır; bütçe üst sınırdır.
- Firma kabul eder → sohbet ve telefonla görüşme. Aynı aracın çakışan kabul işlemleri sunucuda engellenir.
- Firma Anlaştık der → müşteriye firmanın kayıtlı teslim konumu için yol tarifi açılır.
- Firma İşi tamamla der → müşteri değerlendirme yapabilir, iki taraf da şikâyet açabilir. Tamamlanmış/iptal edilmiş işte sohbet, arama ve yol tarifi düğmeleri gösterilmez.
- Uygulama ödeme almaz. Ödeme tarafların kendi anlaşmasıdır.
- Araç kartları geniş ekranda iki sütun, telefonda tek sütundur. Kısa giriş ve aşama animasyonları kullanılır; azaltılmış hareket tercihi gözetilir.

## Eski sürümler

Mevcut rezervasyonların tamamlanabilmesi için geçişte eski kabul edilmiş/tamamlanmış kayıtlar anlaşılmış sayılır. Önceden yayınlanmış uygulamanın doğrudan rezervasyon API'si uyumluluk için korunur. Yeni teklif → görüşme → anlaşma akışı için müşteri ve firma güncel uygulamayı kullanmalıdır.

## Kontroller

- Flutter analizinde sorun bulunmadı; 182 Flutter testi geçti.
- Yerel, üretimden ayrı veritabanında 186 kiralama ve itibar kontrolü geçti.
- PHP sözdizimi kontrolleri geçti; 320, 390, 768 ve 1280 piksel ekran testleri yapıldı.
- Üretim sunucusuna yükleme, fiziksel telefonda push teslimi, telefon araması ve harita uygulamasının açılması bu çalışmada canlı doğrulanmadı.

Yüklemeden sonra aynı şehirde bir müşteri ve bir firma ile teklif → kabul → sohbet/arama → Anlaştık → yol tarifi → tamamla → değerlendirme/şikâyet adımlarını deneyin. Telefon bildirimi için mevcut notification-worker cron görevi ve OneSignal cihaz aboneliği çalışır durumda olmalıdır.
