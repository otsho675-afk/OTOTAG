# Sistem incelemesi — 2 Ekim 2026

Mevcut koyu/neon tasarım korunarak müşteri ve rent a car akışları tamamlandı. Aynı şehir, firma günlük fiyatı, marka/model, 1–365 gün seçimi ve karşılıklı teklif sunucu tarafından doğrulanıyor. Kabul edilen son tutar iş kaydına yazılıyor; eşzamanlı kabul aynı araç için iki rezervasyon oluşturamıyor. Firma kiralamayı tamamladığında araç yeniden listeleniyor. Takvimden ileri tarih seçme bu sürümde yok; rezervasyon mevcut araç uygunluğuna göre yapılıyor.

## Düzeltilenler

- Kilometre hatırlatıcısı araç ve kullanıcı bazında yedi gün bekliyor. Onayda güncel kilometre kaydediliyor; düşen/boş kilometre reddediliyor. “Bir daha gösterme” tercihi çıkış/giriş sırasında korunuyor.
- Kiralama müşteri ekranı 320, 390, 768 ve 1280 piksel genişliklerinde; firma ekleme formu dar ekranda klavye açıkken test edildi. Profil/çıkış erişimi, fiyat doğrulaması, tekrar basma koruması, hata ve boş liste durumları eklendi. Yazılmakta olan filtreler arka plan yenilemesiyle kendiliğinden uygulanmıyor.
- API kullanıcı JWT'sini doğruluyor. Araç, profil, sohbet, özel Pusher kanalı, teklifler ve yönetici işlemlerinde sahiplik/rol kontrolleri güçlendirildi. Sabit yönetici şifresi ve doğrulanmamış OAuth kimliğiyle giriş kaldırıldı.
- Google/Apple sosyal girişte imzalı kimlik tokenı doğrulanıyor. Paket Firebase PHP-JWT kaynağını ve lisansını içeriyor.
- Oturum güvenli depoda tutuluyor; Authorization yalnızca uygulamanın API adresine gönderiliyor. Süresi dolan/bozuk oturum geri yüklenmiyor. Çıkış, kabul edilmiş işi iptal etmiyor.
- Ortak Pusher bağlantısı ekranlar arasında yönetiliyor. Sohbet kanalı bağlanmadığında HTTP yenilemesi devreye giriyor; ekran kapatılınca kendi dinleyicisi temizleniyor.
- Abonelik doğrulamasında gerçek paket/ürün, mağaza işlem kimliği ve bitiş tarihi kullanılıyor. Süresi dolmuş, bekleyen veya iade edilmiş satın alma erişim açmıyor. Sunucu doğrulaması başarısızsa satın alma erken tamamlanmıyor.
- OBD ücretsiz kullanım sayacı başarılı bağlantı sonrası ilerliyor. Komutlar seri gönderiliyor, çakışan telemetri ve zaman aşımı sonrası geç cevaplar sınırlandırılıyor.
- Hesap silme başarısızsa oturum korunuyor. Bildirim planlama başlatılması bekleniyor; kesin alarm izni gerektirmeyen zamanlama kullanılıyor. Araç panelindeki beyaz üstüne beyaz bildirimler düzeltildi.
- Ortak `.env` okuyucusu eklendi: BOM/CRLF, tırnaklı şifreler ve yaygın DB alan adları destekleniyor. Eksik ayar adı 503 cevabında gösteriliyor. CORS hem normal hem hatalı cevaplarda ve OPTIONS isteğinde çalışıyor; yerel geliştirme portları dar kapsamla izinli.
- `env-kurulum.php` mevcut `.env` değerlerini koruyup eksik JWT ve genel servis tanımlayıcılarını ekliyor. Reklam dosyası sunucuda yoksa veri kaydını silmeden boş görsel görünümü kullanılıyor.

## Doğrulama

27 Flutter testi başarılı. Kiralama ekranı geri bildirim sonrası yeniden düzenlendi: kompakt marka/model filtreleri, gün seçici, klavyeyle uyumlu bütçe paneli, neon yeşil tema, daha küçük fotoğrafsız kartlar ve belirgin fiyat/teklif alanları. Bütçenin arama yapılmadan uygulanmaması ve gün seçicinin toplam tutarı güncellemesi doğrulandı. Para, teklif sürümü, kilometre, güvenli oturum, Pusher sahipliği ve responsive ekranlar kontrol edildi. Dart analizinde hata ve uyarı yok; mevcut kodda biçim/stil önerileri devam ediyor.

98 PHP kontrolü başarılı: 31 gerçek MariaDB kiralama kontrolü, 31 gerçek `api.php` HTTP/kurulum kontrolü, 15 abonelik doğrulama kontrolü, 7 imzalı OAuth kontrolü ve 14 yapılandırma kontrolü. HTTP testinde eksik JWT ile 503 oluşturulup kurulum aracı çalıştırıldı; veritabanı ayarları korunarak aynı uç noktadan başarılı cevap alındı. OPTIONS ve kurulumun tekrarında anahtarın korunması da kontrol edildi. Eşzamanlı kabul ve başka kullanıcının kaydına erişim girişimleri kontrol edildi. PHP kaynakları sözdizimi kontrolünden geçti.

Testler ayrı yerel veritabanında çalıştı; üretim sunucusu, kullanıcıların gerçek verileri ve gerçek satın almalar değiştirilmedi.

## Takip edilmesi gerekenler

- aaPanel kurulumu [backend/AA_PANEL_KURULUM.md](backend/AA_PANEL_KURULUM.md) dosyasında. Güncel sunucu ve uygulama birlikte devreye alınmalı; eski token göndermeyen uygulamalar 401 alır. Üretim `.env` değerleri ve Nginx kuralları yerinde doğrulanmalı.
- Git'te daha önce takip edilmiş özel Apple anahtarı ve Android imzalama bilgileri var. `.gitignore` eklemek geçmiş kayıtları kaldırmaz. İlgili anahtarları yenilemek, imzalama bilgilerini güvenli yerel ayarlara taşımak ve Git geçmişini ayrıca temizlemek gerekir.
- Gerçek iOS/Android cihazda sosyal giriş, satın alma/geri yükleme, bildirim, konum ve fiziksel OBD adaptörü denenmeli. Apple/Google abonelik yenileme/iptal olayları için sunucu bildirimleri ve Google Play güncel abonelik API'sine geçiş ayrı iş olarak ele alınmalı.
- Bazı eski API uç noktaları istek sırasında şema kontrolü yapıyor. Yoğun trafik için sürümlü veritabanı migration'ları, iş kuyrukları, ölçüm ve yük testi gerekir; mevcut değişiklikler herhangi bir kullanıcı kapasitesini kanıtlamaz.
- Kiralamada ileri tarih takvimi, müsaitlik aralıkları, teslim/iade kayıtları ve arka planda teklif bildirimi sonraki geliştirmeler olabilir. Bu sürümde açık ekranlar teklifleri sekiz saniyede bir yeniler.

Bu inceleme tüm cihaz ve üretim senaryolarının kusursuz olduğu anlamına gelmez; doğrulanan kapsam ve canlı ortamda kalan kontroller yukarıda belirtilmiştir.
