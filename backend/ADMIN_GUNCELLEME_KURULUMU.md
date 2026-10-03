# Admin paneli ve telefon güncelleme duyuruları

3 Ekim 2026

## Kullanım

Admin panelinde telefonlarda isimleri görünen bölüm menüsü, tablet/masaüstünde yan menü vardır. Genel bakıştan başvurulara, destek taleplerine, firmalara, kiralama canlı takibine ve güncellemelere ulaşılır. Üyeler bölümüne firma filtresi eklenmiştir. Reklam, satın alma, analiz, yedekleme, bakım ve şifre araçları Ayarlar altında korunur. Parça ilanları admin için bütün durumlarda, sayfalar halinde ve veritabanının tamamında arama yapılarak listelenir. Admin çıkışı oturumu da temizler.

1. Yeni uygulama sürümünü Google Play / App Store'da yayımlayın ve seçtiğiniz kullanıcılar için erişilebilir olduğunu doğrulayın.
2. **Güncellemeler** bölümünde Android, iPhone veya iki platformu seçin.
3. Mağazada görünen sürümü `1.0.1` biçiminde girin. İki platformun sürümleri farklı olabilir.
4. Aynı sürüm adında yeni bir derleme yayımladıysanız isteğe bağlı derleme numarasını da girin. Örneğin `pubspec.yaml` içindeki `1.0.0+71`, sürüm `1.0.0`, derleme `71` demektir. Derleme boşsa yalnızca sürüm adı karşılaştırılır. Android versionCode / iPhone CFBundleVersion ile uyumlu bir sayı kullanın.
5. Android bağlantısı `https://play.google.com/store/apps/details?id=com.oto.tag`; iPhone bağlantısı uygulamanın gerçek `https://apps.apple.com/.../id...` adresidir. iPhone mağaza kimliği projede bulunmadığı için uydurulmamıştır; admin bu alanı doldurur.
6. Başlık ve yenilikleri yazın. Varsayılan güncelleme isteğe bağlıdır. Zorunlu seçilirse eski sürümlerde “Daha sonra” gösterilmez; yönetici hesapları paneli kullanmaya devam edebilir.
7. **Önizle ve yayımla** ile içeriği kontrol edin, sonra **Yayımla ve bildir** seçeneğine basın.

Panelde “Gönderim kabul edildi”, bildirim servisinin isteği kabul ettiği anlamına gelir; her telefonun teslim aldığını göstermez. Bildirim izni olmayan veya çevrimdışı telefonlarda anlık push teslimi beklenmez. Uygulama sunucuya erişebildiğinde sürüm kontrolü yapar ve eski sürümde modal gösterir.

**Duyuruyu geri çek** aktif duyuruyu kapatır. Telefon bir sonraki başarılı kontrolde açık modalı kapatır; gönderilmiş sistem bildirimleri geri alınamaz. Önceki zorunlu duyuru kendiliğinden tekrar etkinleşmez.

## Sunucu kurulumu

Teslim edilen backend ZIP'i PHP kaynakları, yardımcılar ve kurulum notlarını içerir. Kimlik bilgisi, `.env`, veritabanı yedeği ve uygulama imzalama dosyası içermez.

1. Sunucu PHP dosyalarını/veritabanını yedekleyin. ZIP içeriğini `/www/wwwroot/eliteagency.sbs/` içinde **api.php ile aynı klasöre** yükleyin; yeni `lib/` klasörü oluşturmayın. Birbiriyle uyumlu dosyaları birlikte yükleyin. `app_updates.php` ve `admin_management.php` yeni zorunlu yardımcılardır.
2. Mevcut `.env` dosyasını koruyun. `ONESIGNAL_APP_ID` ve `ONESIGNAL_REST_API_KEY` değerlerini OneSignal'daki uygulamanın App ID / App API key değerleriyle yapılandırın. FCM ve APNs tarafı bu OneSignal uygulamasına bağlı olmalıdır. API anahtarı Flutter'a konulmaz.
3. PHP PDO MySQL ve cURL etkin olmalı. Veritabanı hesabı ilk istekte `app_update_releases` tablosunu ve indekslerini oluşturabilmeli. Şema bir kez `ototag_schema_migrations` üzerinden oluşturulur; mevcut uygulama kayıtları silinmez.
4. OPcache eski dosyaları tutuyorsa PHP hizmetini yeniden başlatın. `nginx-protect.conf.example` yeni yardımcıların doğrudan HTTP erişimini engelleyen örnek kuralları da içerir. Mevcut eşdeğer kurallarla çakışan bloklar eklemeyin.
5. Geçici push hataları veya yarıda kesilen PHP isteklerinin otomatik yeniden denenmesi için aaPanel zamanlanmış görevinde **her dakika** şu CLI komutunu çalıştırın. Sunucuda seçtiğiniz PHP sürümünün CLI yolunu kullanın:

   ```sh
   php /www/wwwroot/eliteagency.sbs/app-update-worker.php
   ```

İlk gönderim yayınlama isteğinde otomatik denenir. Kuyruk işçisi başarısız gönderimleri artan bekleme süreleriyle, servisin `Retry-After` süresine uyarak yeniden dener. En fazla 5 deneme / ilk 24 saat vardır. İşçi kurulmazsa paneldeki yeniden deneme düğmesi kullanılabilir. Yayından kaldırılan veya yeni sürümle değiştirilen duyuruların bekleyen gönderimleri durur. Aynı kampanyanın tekrarlarında aynı OneSignal idempotency anahtarı kullanılır.

Kaynaklar: [OneSignal bildirim API'si](https://documentation.onesignal.com/reference/push-notification), [platform ve hedef kitle seçimi](https://documentation.onesignal.com/reference/create-message), [tekrar gönderimi önleme](https://documentation.onesignal.com/reference/idempotent-notification-requests).

## Uygulamanın dağıtımı

**Bu güncelleme kontrolünü içeren yeni Android ve iOS derlemesi ilk kez telefonlara dağıtılmalıdır.** Önceden yüklenmiş ve bu kodu içermeyen uygulamalara yalnızca PHP dosyalarını değiştirerek yeni modal eklenemez. Özellik ilk dağıtımdan sonra adminin sonraki sürüm duyurularıyla otomatik çalışır. Windows ortamında iOS derlemesi yapılmadı; Mac/Xcode üzerinden alınmalıdır.

Güncellenmiş web üretim çıktısı `.dart_tool/release_candidate_web/` klasöründedir ve sürümün web ZIP'ine dahil edilmiştir. Webde admin güncelleme yönetimini kullanabilir; telefon güncelleme modalı web kullanıcılarına gösterilmez. Web çıktısını uygulamanın mevcut web dağıtımına yükleyin, API klasöründeki farklı siteyi rastgele değiştirmeyin.

Uygulama gerçek yüklü sürümü `package_info_plus` ile okur. Açılış ekranı bittikten sonra, öne gelince, güncelleme push'u gelince ve öndeyken 5 dakikada bir kontrol eder. Arka planda periyodik kontrol durur; aynı anda kontroller çakışmaz. İsteğe bağlı duyuru 24 saat ertelenebilir. Modal mağazayı açar; uygulama kurulumu telefonun mağaza akışıyla yapılır.

Sunucuya veya mağazalara bu görev sırasında canlı dağıtım yapılmadı. Canlı OneSignal bildirimi gönderilmedi; servis kabulü/teslimi canlı ortamda ayrıca doğrulanmalıdır.

## Doğrulama

- Android/iPhone sürüm ve derleme karşılaştırması, mağaza bağlantıları, zorunlu modal, mağaza açma hatası, erteleme, duyuru geri çekme, açılış ve yaşam döngüsü testleri.
- Admin arayüzü 320, 390, 768 ve 1280 pikselde büyük yazıyla kontrol edildi; yayınlama ancak geçerli form ve onaylanan önizlemeden sonra API çağrısı yapar.
- İzole MySQL veritabanında yetkiler, atomik iki platform yayını, sürüm düşürme reddi, idempotency, push yeniden deneme ve bütün durumlarda parça ilanı arama/sayfalama testleri.
- Flutter web üretim derlemesi başarıyla tamamlandı.
