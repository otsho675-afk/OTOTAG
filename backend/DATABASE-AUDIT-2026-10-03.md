# Veritabanı incelemesi — 3 Ekim 2026

İncelenen dosya: kullanıcının sağladığı `elite (1).sql` yedeği.
Canlı sunucu bu inceleme sırasında değiştirilmedi. Yedek içindeki SQL çalıştırılmadı;
INSERT kayıtları yerel olarak ayrıştırıldı ve bağlantıları karşılaştırıldı.

## Bulgular

- 23 kullanıcı, 13 araç, 30 iş, 10 araç geçmişi, 45 uygulama içi bildirim.
- Bildirim kuyruğu: 10 `no_subscribers`, 1 `sent`. `sent`, servis kabulüdür;
  telefona teslimat kanıtı değildir. 10 eski kaydı tekrar gönderime açmadık.
- Araç 22 / kullanıcı 45 için 5 Ekim tarihli muayene doğru; 3 Ekim'de iki gün kalır.
  Bu araç için gönderim 11, OneSignal tarafından kabul edilmiş.
- Kullanıcısı bulunmayan araçlar: 5, 6, 8, 9.
- Aracı bulunmayan geçmiş kayıtları: 1, 2.
- Kullanıcısı bulunmayan uygulama içi bildirim: 22.
- Müşterisi bulunmayan iş: 327; zaten `cancelled`.
- İşi bulunmayan mesaj: 33; işi bulunmayan değerlendirme: 25.
- Sağlayıcısı bulunmayan kiralık araç kaydı: 1.
- Aynı kullanıcının normalize edilmiş aynı plakalı mükerrer aracı bulunmadı.
  Farklı hesaplar aynı plakayı kullanıyor; sahiplik doğrulanmadan birleştirilmedi.
- Kuyruk payload JSON'ları geçerli; kayıtlı OAuth kimlikleri mükerrer değil.
- Araç sahipliği, araç geçmişi ve kullanıcı bildirim sorgularında uygun indeks yok.
- İş tablosunda aynı kolonları kullanan birden fazla indeks var. Uygulama
  migrasyonları ve adla indeks kullanımı incelenmeden indeksler silinmedi.

## Düzeltme

`database-repair-2026-10-03.sql`, üç sorgu indeksini tekrar çalıştırılabilir
şekilde ekler. Tarih, araç sahipliği, abonelik veya eski işlem geçmişi değiştirmez.
Yetim kayıtların doğru sahibi bu yedekten belirlenemiyor; geçmişi silmek veya
başka bir kullanıcıya bağlamak yerine raporlandı.

Hatırlatma eksikliği bir tablo bozulması değildi: worker aynı gün ikinci kez
araçları taramıyordu. `notification-worker.php` ve `notification_delivery.php`
artık saat 09.00'dan sonra beş dakikada bir yeni/değişmiş araçları tarar.
Araç/tarih/aşama benzersiz anahtarı tekrar gönderimi engeller. İki gün ve bir gün
kalan tarihler aynı üç-gün aşamasıdır; her gün yeni uyarı üretmez. Son gün ve
gecikme aşamalarında yeni uyarı üretilir. Cihazı olmayan eski uyarılar ve süresi
dolmuş gönderimler bu değişiklikle yeniden gönderilmez.

## Sunucuya uygulama

1. Mevcut yedeği saklayın; bu yedeği canlı veritabanına tekrar içe aktarmayın.
2. Sunucunun PHP dosyalarının bulunduğu dizine `notification_delivery.php`
   (`lib` kaynağından) ve `notification-worker.php` (`backend` kaynağından) yükleyin.
3. `elite` veritabanı seçiliyken düzeltme SQL dosyasını phpMyAdmin'de içe aktarın.
4. Mevcut dakikalık cron görevini koruyun. Worker'ı bir kez elle çalıştırın.
5. Yeni/değişmiş bir aracın hatırlatması en geç sonraki beş dakikalık taramada
   kuyruğa girmeli; tekrar taramada aynı aşama için ikinci gönderim oluşmamalı.

## Doğrulama sınırı

Yedek ayrıştırma ve kayıt bağlantısı kontrolleri tamamlandı. PHP/MySQL regresyon
testleri yerelde PHP/MySQL çalıştırıcısı olmadığı için bu ortamda çalıştırılamadı.
iPhone'a gerçek teslimat veritabanı yedeği ile doğrulanamaz; OneSignal teslimat
raporu ve cihaz üzerinde test gerekir.
