# OTOTAG — Son sistem güncellemesi

Tarih: 3 Ekim 2026. Bu paket mevcut Rent A Car, müşteri ve usta akışlarının üzerine yapılan hata, güvenlik ve performans düzeltmelerini içerir. Mevcut siyah/yeşil görünüm korunmuştur.

## Sunucuya yükleme

1. Mevcut PHP dosyalarını ve veritabanını yedekleyin.
2. `OTOTAG-son-sistem-guncelleme.zip` içeriğini aaPanel'de `/www/wwwroot/eliteagency.sbs/` içindeki **api.php ile aynı klasöre** açın. Tüm PHP dosyalarını ve `php_jwt/` klasörünü birlikte yükleyin. Sunucuda ayrıca `lib/` alt klasörü oluşturmayın.
3. Yeni **api_runtime.php** zorunludur; api.php ve diğer yardımcılar tarafından çağrılır. Pakette `.env`, servis hesabı, özel anahtar veya SQL yedeği bulunmaz. Mevcut `.env` değerlerini koruyun.
4. PHP OPcache eski dosyaları tutuyorsa ilgili PHP hizmetini yeniden başlatın. PDO MySQL, cURL, OpenSSL ve yazılabilir fotoğraf yükleme klasörü gerekir.
5. Yeni şema tamamlanma kayıtları `ototag_schema_migrations` tablosunda tutulur. İlk çalışmada veritabanı hesabının tablo ve indeks oluşturma/değiştirme yetkisi gerekir. Mevcut kayıtlar silinmez. Rezervasyon tabloları InnoDB olmalıdır; uyumsuz motor sessizce kullanılmaz.

`nginx-protect.conf.example` aaPanel Nginx yapılandırmasına uygulanabilecek koruma kurallarını içerir. Bu bir örnektir, ZIP'i açmak Nginx ayarını otomatik değiştirmez. Mevcut eşdeğer kurallarla çakışan location blokları eklemeyin. `.env`, yedekler, loglar ve yardımcı PHP dosyalarının doğrudan HTTP üzerinden okunması engellenmelidir.

ZIP backend'i günceller. Uygulama değişiklikleri için yeni Flutter derlemesi kullanın:

- Android test APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Güncel web üretim çıktısı: `.dart_tool/system_final_web_build/`. Bunu Flutter uygulamasının gerçek web dağıtımına yükleyin; API klasöründeki tanıtım sitesini rastgele değiştirmeyin.
- iOS: Mac üzerinden yeni build/TestFlight gerekir. Windows'ta iOS derlemesi yapılmadı.

## Bu incelemede düzeltilenler

- **Oturum ve çıkış:** Oturum yazma/temizleme işlemleri sıraya alındı. Eski bir isteğin 401 yanıtı yeni açılmış hesabı kapatamaz. Geçerli oturumun süresi dolduğunda giriş ekranına dönülür. Güvenli depolama silme işlemi başarısız olsa bile kalıcı çıkış işareti eski hesabın tekrar açılmasını engeller. Eski tercih kayıtları tek başına dashboard açamaz. Oturum geçersizleşince mobil bildirim hesabı da kapatılır.
- **Başlangıç:** Bildirim servisindeki başlatma hatası uygulamanın açılmasını engellemez. Mobil eklentiler web/masaüstü ortamında yanlışlıkla başlatılmaz. HTTP bağlantılarında süre ve bağlantı sınırı vardır; TLS sertifikası kontrolünü devre dışı bırakan override kaldırıldı.
- **Harita anahtarı:** Android native harita metadata'sı ve Flutter ekranları aynı `config.env` içindeki `GOOGLE_MAPS_API_KEY` değerini kullanır. Native Android için isteğe bağlı `OTOTAG_GOOGLE_MAPS_API_KEY` Gradle/ortam değişkeni, Flutter için `MAPS_API_KEY` dart-define önceliği vardır. Kaynak dosyadaki sabit harita anahtarı kaldırıldı. Anahtar değeri değiştirilmedi.
- **Harita doğruluğu:** Gerçek ustaları temsil etmeyen rastgele hareket eden araç simülasyonları kaldırıldı. Bu değişiklik yeni bir yakındaki ustalar servisi oluşturmaz. Gerçek eşleşme sonrasındaki konum ve rota akışı korunur. Eski adres yanıtı yeni seçilen konumu ezemez; başarısız sorgu yükleme göstergesini açık bırakmaz. iOS adres çözümlemesi yerel geocoding servisini kullanır. Geçersiz koordinatlar reddedilir.
- **Gereksiz sorgular:** Usta ve iş takip haritalarının periyodik HTTP sorguları önceki yanıtı bekler. Canlı kanal gerçekten bağlıyken yedek sorgu aralığı 15 saniye, bağlantı yokken 5 saniyedir. Bu aralıklar GPS kaynaklı veya kullanıcı tarafından başlatılan sorgulardan ayrıdır. Sorgu yardımcı sınıfı hata durumunda bekleme süresini artırabilir. Arka planda periyodik sorgular durur. Rent A Car/müşteri ekranlarında bekleyen yenilemenin arka planda yeni istek başlatması da engellendi.
- **Dashboard ve görünüm:** Paralel dashboard yenilemeleri engellendi; reklam zamanlayıcısı arka planda tekrar başlayamaz. Araç carousel'inin aynı genişlik için tekrar controller oluşturması düzeltildi. Büyük yazıda usta bilgi kartları aynı yükseklikte hizalanır; kazanç Türkçe para biçimindedir. Genel metin ölçeği sistem tercihine göre, en fazla 1,4 olacak şekilde ayarlanır. Eksik Cupertino ikon fontu eklendi.
- **Backend yanıtı:** Dizi gönderilmiş telefon/kimlik gibi alanlar, geçersiz işlem adları ve aşırı büyük metinler SQL'e veya tipli doğrulayıcılara ulaşmadan reddedilir. Beklenmeyen PHP hataları boş HTML/JSON yerine anlaşılır JSON ve hata referansı verir; açık transaction geri alınır. HTTP 500 yanıtları SQL/şifre ayrıntılarını kullanıcıya göstermez. Bozuk UTF-8 JSON yanıtını boş bırakmaz.
- **Veritabanı performansı:** Kiralama şeması ve eşleşme indekslerinin tamamlanması veritabanında kaydedilir; aynı ağır şema kontrolü her istekte tekrarlanmaz. Eşleşme için şehir/hizmet/durum ve firma/durum indeksleri, hesap için telefon/rol indeksi eklenir; eşdeğer mevcut indeksler yeniden oluşturulmaz. Başarısız migration tamamlandı olarak işaretlenmez. InnoDB kontrolü tamamlanma kaydından sonra da sürer.
- **Diğer:** Bildirim anahtarları eksikse boş anahtarla Pusher/OneSignal isteği gönderilmez. Toplu geçmiş silme en fazla 100 geçerli pozitif işlem kimliği kabul eder; JSON içine gizlenen dizi ve aşırı uzun kimlik listeleri engellenir.

Önceki aynı şehir + günlük fiyat × gün sayısı ≤ toplam bütçe eşleşmesi, rezervasyon çakışma kontrolleri, fiyat sürümleri, geçmiş, şikâyet, doğrulanmış değerlendirme ve admin izleme akışları korunur ve tekrar test edilmiştir.

## Kontrol sonuçları

| Kontrol | Sonuç |
| --- | --- |
| Flutter testleri | 122 geçti |
| Kiralama/rezervasyon/değerlendirme | 178 geçti |
| Gerçek api.php üzerinden localhost HTTP testleri | 133 geçti |
| Runtime ve migration kontrolleri | 15 geçti |
| Abonelik ve sayfalama | 43 geçti |
| Fotoğraf yükleme/eksik uzantı/uyumsuz DB motoru | 33 geçti |
| Makbuz doğrulama, OAuth, yetki/rota, env kuralları | 68 geçti |
| PHP sözdizimi | 13 backend dosyası geçti |
| Dart statik analiz | Hata ve uyarı yok; 269 bilgi düzeyinde stil önerisi mevcut |
| Android debug ve web üretim derlemesi | Başarılı |

Backend toplamı 470 kontrol. Backend testleri port 33307'deki ayrı yerel veritabanlarında çalıştırıldı; canlı sunucu/veritabanı değiştirilmedi. Mobil görünüm testleri 320, 390, 768 ve 1280 genişliklerini, klavyeyi ve büyük yazıyı kapsar. Ekran görüntüleriyle giriş, kiralama ve usta paneli görünümü de kontrol edildi.

## Canlıda ayrıca doğrulanması gerekenler

Fiziksel iPhone/Android, gerçek GPS/arka plan davranışı, uzak sunucu ve gerçek ücretli mağaza işlemi bu yerel kontrollerle doğrulanmış sayılmaz. Gerçek mağaza ödeme entegrasyonu ve sunucu makbuz doğrulaması mevcut; ürünlerin, mağaza yetkilerinin ve servis hesabının doğru yapılandırıldığı ayrıca sandbox/TestFlight/Play dahili testinde denenmelidir. Uygulama dışında yenileme/iade bildirimleri için Apple/Google webhook kurulumu hâlâ ayrı iştir.

Google localhost `origin_mismatch` Console'daki Web OAuth istemcisinin izinli origin ayarına bağlıdır. Harita SDK yetkileri/kısıtlamaları ve backend yol rotası servisinin sunucu ayarları da ayrıca geçerli olmalıdır. Yerel anahtar bağlantısı, uzak servis izinlerinin açık olduğunu kanıtlamaz.

Android derlemesinde bazı eklentilerin ilerideki Flutter sürümleri için Kotlin geçiş uyarısı vardır; mevcut derleme başarılıdır. Bir kapasite/yük testi yapılmadı; belirli eşzamanlı kullanıcı sayısı veya sıfır hata garantisi verilmez.
