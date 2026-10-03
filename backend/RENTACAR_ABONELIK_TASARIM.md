# OTOTAG — Rent A Car, abonelik ve tasarım güncellemesi

## Sunucuya kurulumu

1. aaPanel'de `/www/wwwroot/eliteagency.sbs/` klasöründeki mevcut PHP dosyalarını yedekleyin.
2. `OTOTAG-rentacar-abonelik-tasarim.zip` içeriğini **api.php'nin bulunduğu klasöre** açın. PHP dosyaları ve `php_jwt/` doğrudan bu klasörde olmalı; ayrıca bir `lib/` klasörü açmayın.
3. Sunucudaki mevcut `.env` dosyasını koruyun. Bu ZIP `.env`, servis hesabı anahtarı veya veritabanı yedeği içermez. `.env` yükleyicisini yeniden çalıştırmanız gerekmez.
4. PHP'de PDO MySQL, cURL ve OpenSSL etkin olmalı. API'nin veritabanı kullanıcısının gerekli şema güncellemelerini yapabilmesi gerekir. Eksik abonelik sütunları ve satın alma tablosundaki Rent A Car rolü işlem başlamadan önce otomatik eklenir. Veriler sıfırlanmaz.
5. Sunucu PHP OPcache eski dosyaları gösteriyorsa aaPanel'deki ilgili PHP hizmetini yeniden başlatın. `/uploads/rentacar/` PHP kullanıcısı tarafından yazılabilir olmalı.

## Uygulamadaki değişiklikler

- Telefon ve şifre etiketleri artık alanların üzerinde, kesilmeden gösteriliyor. Web'deki Google girişi açık Web OAuth istemci kimliği ve Google'ın kendi giriş düğmesiyle çalışıyor.
- Yeni araç işlemi üç adımdan oluşuyor: **kategori → bilgiler → kontrol ve belge**. Geri gidince yazılan bilgiler korunuyor; kaydetmeden önce tutar ve kilometre doğrulanıyor. Alttaki devam/kaydet düğmesi klavyenin üzerinde kalıyor.
- Müşteri hizmet kartlarında Yıkama ilk sıraya, Araç Kirala en alta geniş karta taşındı.
- Rent A Car üç nokta menüsü açıklamalı, ikonlu bir alt panel oldu. Firma hesabı, abonelik, arıza tespit, müşteriye görünen profil ve geçmiş işlemler buradan açılıyor.
- Firmanın özel profilinde iletişim, kayıtlı konum bağlantısı, abonelik ve değerlendirmeler yer alıyor. Müşterinin gördüğü firma profilinde yorumlar, yıldızlar ve mevcut puana göre hesaplanan rozetler var. Özel abonelik verileri bu profile gönderilmiyor.
- Araç aramada marka, model, gün sayısı ve **toplam bütçe** aynı panelde. Günlük ücret × gün sayısı bütçeyi aşan araç eşleşmez. Örneğin 5.000 TL/gün olan araç 3 gün ve 5.000 TL toplam bütçe ile görünmez; bunun için en az 15.000 TL gerekir.
- Müşteri araçları tek sütunda kısa kartlarla listeleniyor. Sayfa başına 12 araç; önceki/sonraki sayfa var. Filtre değişince ilk sayfaya dönülüyor. Aynı şehir, aktif hesap, müsait araç ve geçerli firma üyeliği koşulları sunucuda kontrol ediliyor.
- Arıza tespit ekranı web'de yerel arıza kodu sözlüğünü açıyor. Canlı araç okuması mobil cihaz, desteklenen Wi-Fi/TCP ELM adaptörü ve gerçek araç bağlantısı gerektiriyor; web tarayıcısı doğrudan TCP bağlantısı açamaz. Ekran adaptör olmadan canlı veri üretmez.

## Aylık üyelik ve mağaza ayarları

Rent A Car için kayıt tarihinden itibaren mevcut sistemdeki 30 günlük işletme denemesi kullanılır. Daha sonra işletme aylık üyeliği gerekir. **Arıza tespit işletme üyeliğine dahildir.** Süresi dolan firma yeni eşleşme/rezervasyon alamaz; mevcut işini bitirebilir, geçmişini görebilir ve şikayet işlemlerini sürdürebilir.

Yeni ödeme sayfası mağazanın güncel yerel fiyatını gösterir. Ürün bulunmadan ödeme düğmesi açılmaz. Satın alma sunucuda Apple/Google ile doğrulandıktan sonra üyelik tanınır; cihazdaki tercihler üyelik vermez. Geri yüklenen makbuz gün sayısı eklemez, mağazanın gerçek bitiş tarihini kullanır. Aynı makbuzun başka hesaba geçirilmesi engellenir.

| Amaç | Google Play ürün kimliği | Apple ürün kimliği |
| --- | --- | --- |
| İşletme / Rent A Car aylık üyeliği | `provider_monthly_subscription` | `ototag_provider_monthly` |
| Ayrı arıza tespit üyeliği | `diagnostic_monthly_100tl` | `diagnostic_monthly_100tl` |

Bunlar uygulamanın mevcut ürün kimlikleridir. Konsollarda ilgili uygulamada etkin, bir aylık otomatik yenilenen abonelik olarak tanımlanmalıdır. Arıza ürününün kimliğindeki `100tl` ekran fiyatı değildir; uygulama fiyatı mağazadan okur. Rent A Car'a ayrıca bu ürün satılmaz; işletme üyeliği kullanılır.

Sunucunun mevcut `.env` dosyasında:

- `APPLE_SHARED_SECRET`: App Store Connect'ten alınmış gerçek paylaşılan gizli anahtar. Açıklama metni veya örnek değer kabul edilmez.
- `APPLE_BUNDLE_ID`: mevcut iOS uygulama kimliğiyle aynı olmalı (`com.oto.tag`).
- `ANDROID_PACKAGE_NAME`: mevcut Android paket kimliğiyle aynı olmalı (`com.oto.tag`).
- `GOOGLE_SERVICE_ACCOUNT_PATH`: Android Publisher erişimi olan servis hesabının JSON dosyasının **sunucudaki mutlak yolu**. Örneğin `/www/server/private/ototag-play-service-account.json`. Bu dosya ZIP'te yoktur; Web OAuth istemci kimliği bu dosyanın yerine geçmez. Dosyayı web kökü dışında saklayın ve PHP kullanıcısına okuma izni verin. Servis hesabına Play Console'da uygulamanın satın alma/abonelik doğrulama erişimi de verilmelidir.

Eksik veya yetkisiz mağaza bağlantısı artık genel bir 500 yerine açıklamalı bir yapılandırma hatası döndürür. Sahte/geçersiz makbuzla üyelik açılmaz.

Mağaza yapılandırması bu çalışma sırasında uzak konsollarda değiştirilmedi. Gerçek ücretli satın alma yapılmadı. Apple sandbox/TestFlight ve Google Play dahili test dağıtımı ile satın alma → sunucu doğrulama → geri yükleme akışını kendi mağaza hesaplarınızla kontrol edin. Doğrudan kurulan debug APK, Play ürünlerinin gösterilmesi ve ödeme testi için yeterli olmayabilir.

Bu güncelleme mağaza makbuzlarını ve geri yüklemeyi işler. Apple sunucu bildirimleri / Google RTDN webhook kurulumu içermez. Uygulama dışında gerçekleşen yenileme veya iade değişikliklerini anında sunucuya aktarmak için ayrıca bu bildirimlerin bağlanması gerekir; mevcut akış sunucunun kaydettiği doğrulanmış bitiş tarihini kullanır.

Resmî mağaza belgeleri: [Apple abonelikleri](https://developer.apple.com/app-store/subscriptions/), [Google Play abonelik planları](https://support.google.com/googleplay/android-developer/answer/12154973), [Android Publisher servis hesabı kurulumu](https://developers.google.com/android-publisher/getting_started), [Flutter satın alma ve geri yükleme](https://pub.dev/packages/in_app_purchase).

## Web Google girişi

Web istemci kimliği uygulamadaki mevcut Web OAuth kimliğiyle ayarlandı. `GOOGLE_WEB_CLIENT_ID` dart-define ile değiştirilebilir. Backend'deki `GOOGLE_OAUTH_CLIENT_IDS` izin listesi bu Web kimliğini içermelidir.

Google Cloud Console → ilgili **Web application** OAuth istemcisi → **Authorized JavaScript origins** bölümüne kullanılan gerçek origin eklenmelidir. Örnekler `https://eliteagency.sbs` ve sabit geliştirme portunuz için `http://localhost:60369`. Şema, alan adı ve port eşleşmelidir; buraya `/api.php` eklemeyin. Flutter'ın rastgele geliştirme portu yerine kayıtlı sabit portu kullanın. Backend CORS ayarı Google Console origin izninin yerine geçmez.

[Google'ın resmî Web istemci kimliği / origin kurulumu](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid).

## Doğrulama ve uygulama dağıtımı

- 87 Flutter testi geçti: ödeme doğrulama sırası, tekrar makbuz, geri yükleme, rol/profil ayrımı, sayfalama, işlem adımları ve dar ekranlar dahil.
- 350 kiralama/backend kontrolü ve 15 makbuz normalleştirme kontrolü geçti. Testler yalnızca yerel, izole test veritabanlarında çalıştırıldı.
- PHP dosyaları sözdizimi kontrolünden geçti. Dart analizinde hata veya uyarı yok; mevcut bilgi düzeyindeki lint notları devam ediyor.
- Android debug APK ve web üretim derlemesi tamamlandı. 320, 390, 768 ve mevcut geniş ekran testleri çalıştırıldı. Fiziksel iPhone/Android cihaz testi ve gerçek mağaza ödemesi yapılmadı; iOS bu Windows makinesinde derlenmedi.

**Backend ZIP'i tek başına telefon arayüzünü güncellemez.** Flutter kaynakları bu projede güncellendi. Android için `build/app/outputs/flutter-apk/app-debug.apk` test edilebilir. Web derlemesi `.dart_tool/rental_web_build/` içindedir; web uygulamanızın mevcut dağıtım hedefinde kullanılmalıdır. API klasöründeki mevcut tanıtım sitesinin `index.html` dosyasının üzerine rastgele yazmayın. iOS dağıtımı için Mac üzerinden yeni build/TestFlight gerekir.

ZIP içindeki `SHA256SUMS.txt`, paketlenen PHP ve bağımlılık dosyalarının bu çalışma anındaki SHA-256 özetlerini içerir.
