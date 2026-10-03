# OTOTAG — Giriş, ödeme, usta paneli ve rota güncellemesi

## Sunucuya yükleme

`OTOTAG-giris-usta-harita-guncelleme.zip` içeriğini aaPanel'de `/www/wwwroot/eliteagency.sbs/` içindeki **mevcut api.php ile aynı klasöre** açın. Önce mevcut PHP dosyalarını yedekleyin. Paketteki tüm PHP dosyaları ve `php_jwt/` birlikte yüklenmeli; ayrıca `lib/` alt klasörü oluşturmayın. Yeni yardımcı dosyalar `api.php` tarafından çağrılır.

**Mevcut `.env` korunur. ZIP içinde `.env`, özel anahtar, servis hesabı JSON'u veya veritabanı yedeği yoktur.** Dosyalar OPcache nedeniyle güncellenmezse ilgili PHP hizmetini yeniden başlatın. PDO MySQL, cURL, OpenSSL ve dosya yükleme izinleri mevcut olmalı. Gerekli şema eklemeleri mevcut veriler korunarak yapılır.

ZIP yalnızca backend'i günceller. Arayüz için yeni Flutter build gerekir. Android debug APK: `build/app/outputs/flutter-apk/app-debug.apk`. Web üretim çıktısı: `.dart_tool/auth_maps_web_build/`. Bu web çıktısını uygulamanın gerçek web dağıtımına yükleyin; API klasöründeki mevcut tanıtım sitesinin index.html dosyasını rastgele değiştirmeyin. iOS için Mac üzerinden yeni build/TestFlight gerekir.

## Giriş ve zorunlu kayıt bilgileri

- Giriş ekranı kompakt siyah/yeşil görünüme döndü. Telefon ve şifre başlıkları alanların üzerinde; Google ve Apple seçenekleri yan yana.
- Web Google düğmesi Google'ın resmi kimlik bileşenini kullanır. Giriş, kayıt ve profil üzerinden hesap bağlama aynı doğrulanmış kimlik akışını kullanır.
- Telefon `0`, `+90` veya `0090` biçiminden aynı numaraya dönüştürülür. Ad, geçerli telefon ve listeden şehir seçimleri sunucuda da zorunludur.
- Sosyal giriş kayıt bilgilerini atlamaz. Eksik eski sosyal hesap, doğrulanmış aynı Google/Apple kimliği ile kayıt tamamlama ekranına gider. Tamamlanmış hesabın başka telefonla yeniden yazılması engellenir. Kimlik sağlayıcısının imzası, uygulama kimliği ve geçerlilik süresi doğrulanır.
- İşletmelerde IBAN, hizmete uygun belgeler ve firma konumu/hizmet aracı plakası zorunludur. Rent A Car kaydı yönetici onayı bekler. Firma, usta girişinden girse de Rent A Car rolünü korur. Usta ile Rent A Car aynı işletme telefon giriş alanını paylaşır; çakışan ikinci kayıt engellenir.
- Apple girişi native iOS'ta kullanılabilir. Web Apple için gerçek Service ID ve HTTPS dönüş adresi yapılandırılmadığında düğme kapalıdır. Bu bilgiler `APPLE_SERVICE_ID` ve `APPLE_REDIRECT_URI` dart-define değerleridir; backend'in `APPLE_OAUTH_CLIENT_IDS` listesi kullanılan Service ID'yi de içermeli.

## Localhost Google hatasını giderme

Google Cloud Console → APIs & Services → Credentials → uygulamanın **Web application** OAuth istemcisi → **Authorized JavaScript origins**:

```text
http://localhost
http://localhost:60369
```

Proje kökündeki `run-web-test.ps1` geliştirme portunu 60369 olarak sabitler. Farklı port veya 127.0.0.1 kullanırsanız kullanılan origin ayrıca kaydedilmelidir. Origin içine `/api.php` yazmayın. Üretimde kullanılan HTTPS uygulama origin'i de eklenmeli. Bu ayar Google Console'dadır; `.env` içindeki CORS listesi Google'ın `origin_mismatch` hatasını çözmez.

Uygulamadaki `GOOGLE_WEB_CLIENT_ID` ile sunucudaki `GOOGLE_OAUTH_CLIENT_IDS` izin listesi aynı Web istemci kimliğini içermeli. Bu çalışmada uzak Google/Apple konsolları değiştirilmedi. [Google'ın resmi localhost/origin kurulumu](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid).

## Gerçek mağaza ödemesi

**Kod gerçek Apple App Store / Google Play satın alma API'sini kullanır. Canlı mağaza kurulumunun tamamlandığı veya gerçek ödeme alındığı bu çalışma ile doğrulanmış değildir.** Testler kontrollü makbuz ve mağaza cevaplarıyla yapıldı; ücretli işlem yapılmadı.

| Amaç | Google Play ürün kimliği | Apple ürün kimliği |
| --- | --- | --- |
| Müşteri Premium Garaj | `customer_premium_monthly` | `ototag_premium_monthly` |
| Usta / Rent A Car aylık işletme üyeliği | `provider_monthly_subscription` | `ototag_provider_monthly` |
| Ayrı arıza tespit üyeliği | `diagnostic_monthly_100tl` | `diagnostic_monthly_100tl` |

İşletme üyeliğine arıza tespit erişimi dahildir. Mevcut 30 günlük deneme bittikten sonra doğrulanmış aylık işletme üyeliği gerekir. Ürünler ilgili mağazada etkin aylık abonelik olarak tanımlanmalı. Ekran fiyatı mağazadan gelir; ürün kimliğindeki sayı fiyat olarak kullanılmaz.

Müşteri, usta ve firma ödeme ekranları ortak siyah/yeşil tasarımı kullanır. Mağaza fiyatı bulunamazsa satın alma kapalıdır; yeniden deneme ve satın alımları geri yükleme seçenekleri vardır. Satın alma sunucuda doğrulanmadan üyelik açılmaz. Yinelenen makbuz yeni gün eklemez; gerçek mağaza bitiş tarihi kullanılır. Başka hesabın makbuzu devralınamaz.

Sunucunun mevcut `.env` dosyasında gerçek `APPLE_SHARED_SECRET`, `APPLE_BUNDLE_ID`, `ANDROID_PACKAGE_NAME` ve `GOOGLE_SERVICE_ACCOUNT_PATH` değerleri gerekir. Google servis hesabının Android Publisher/Play abonelik doğrulama yetkisi olmalı. JSON dosyası web kökü dışında tutulur; Web OAuth client ID bu servis hesabının yerine geçmez. Eksik yapılandırma açıklamalı hata verir, üyelik açmaz.

Apple sandbox/TestFlight ve Google Play dahili test dağıtımında satın alma → sunucu doğrulama → geri yükleme kontrol edilmelidir. Debug APK Play ödeme testinin yerine geçmez. Apple sunucu bildirimleri ve Google RTDN webhook kurulumu bu pakette yoktur; uygulama dışında gerçekleşen yenileme/iade olayları anlık webhook ile izlenmez. Mevcut akış doğrulanmış makbuz ve kaydedilmiş bitiş tarihini kullanır.

[Apple abonelikleri](https://developer.apple.com/app-store/subscriptions/), [Google abonelik planları](https://support.google.com/googleplay/android-developer/answer/12154973), [Google servis hesabı kurulumu](https://developers.google.com/android-publisher/getting_started).

## Usta paneli ve eşleşme

- Usta ana panelinde aylık kazanç ve gerçek değerlendirme bilgileri, çevrimiçi olma düğmesi ve beş bölümlü alt menü var. Henüz değerlendirme yoksa sahte beş yıldız gösterilmez.
- İş önizlemeleri sadeleştirildi. İş geçmişi tamamlanan/iptal/yüksek kazanç filtreleri ve sekiz kayıtlık sayfalarla düzenlendi. Mevcut iş detayları ve geçmişten kaldırma akışı korunur.
- Eşleşme şehir, hizmet türü, mesafe, aktif müşteri/usta hesabı ve geçerli işletme üyeliği ile sunucuda doğrulanır. Çekiciye tamirci taleplerinin gelmesine neden olan hizmet kategorisi sorgusu düzeltildi.
- Doğrudan API çağrısıyla yanlış şehir veya hizmete teklif verilemez. Usta satırı işlem sırasında kilitlenir; ikinci aktif işe eşleşmesi engellenir. Kabul edilmiş işin fiyatı karşı teklifle değiştirilemez. Kabulde cihazın gönderdiği tutar yerine sunucuda kayıtlı teklif kullanılır.
- Rent A Car'ın aynı şehir ve **günlük fiyat × gün sayısı ≤ toplam bütçe** kuralı korunur. Örneğin 5.000 TL/gün araç üç gün için 15.000 TL toplam bütçe ister.

## Rota yapılandırması

Rota isteği artık doğrulanmış aktif iş üzerinden sunucuya gider. Hedef konum iş kaydından alınır; ilgisiz hesaplar rota verisini alamaz. Google rota anahtarı telefonun URL parametresinde taşınmaz. GPS doğruluğu düşük ölçümler ve geç gelen eski rota cevapları elenir. Rota üzerinde segment hesabı kullanılır; uzun bir yol parçasında yalnızca köşe noktası uzak diye gereksiz yeniden rota alınmaz.

**Google harita üzerinde yol rotası ve trafik süreleri için:** sunucunun mevcut `.env` dosyasına gerçek `MAPS_ROUTES_API_KEY` eklenmeli; ilgili Google projesinde Routes API ve faturalandırma etkin olmalı. Anahtar sunucu için sınırlandırılmalı. Mevcut `MAPS_API_KEY` yedek olarak okunur, ancak mobil SDK için kısıtlanmış anahtar sunucudaki Routes API'yi açmayabilir. Google Maps native/web SDK anahtarları ayrı mevcut platform ayarlarını kullanır.

**Apple harita üzerine yol rotası çizmek için:** bağımsız bir OSRM yol servisi kullanılmalıdır. Mevcut `.env` içinde `OSRM_BASE_URL` gerçek HTTPS servis adresi olmalı; URL'nin sonuna `/route/v1/...` eklemeyin. Herkesin kullandığı demo sunucusuna varsayılan olarak istek atılmaz. OSRM gerçek zamanlı trafik süresi iddiasında bulunmaz. Google rota verisi Google haritalarında gösterilir ve burada önbelleğe alınmaz; Apple haritaya Google geometrisi taşınmaz.

Yol servisi yapılandırılmadıysa veya cevap vermezse sahte düz çizgi ve tahmini dakika gösterilmez. Yeniden deneme ve dış Google/Apple Haritalar navigasyonu kullanılabilir. Web Safari'de native Apple Maps bileşeni açılmasına neden olan platform kontrolü de düzeltildi. Harita atıfları alt panellerin arkasında kalmaması için harita boşlukları ayarlandı.

[Google Routes kurulum/anahtar](https://developers.google.com/maps/documentation/routes/get-api-key), [Google rota hesaplama](https://developers.google.com/maps/documentation/routes/compute_route_directions), [Google rota kullanım kuralları](https://developers.google.com/maps/documentation/routes/policies).

## Kontroller

- 106 Flutter testi geçti; 320, 390, 768 ve 1280 piksel ekranlar, klavye açık formlar, büyük yazı, geçmiş filtreleri/sayfalama, ödeme doğrulama sırası ve rota geometrisi dahil.
- 380 kiralama/gerçek API/abonelik/yükleme kontrolü geçti: 178 + 126 + 43 + 33. Ayrıca 15 makbuz, 7 imzalı OAuth, 32 kayıt/rota kuralı ve 14 ortam yapılandırması kontrolü geçti. Veritabanı testleri yalnızca ayrı yerel test veritabanlarında çalıştı.
- 12 backend PHP dosyası sözdizimi kontrolünden geçti. Dart analizinde hata ve uyarı yok; mevcut bilgi düzeyindeki lint notları sürüyor.
- Android debug ve web üretim derlemeleri hazırlandı. Fiziksel telefon, gerçek Google/Apple oturumu, canlı rota servisi ve mağaza sandbox satın alması bu ortamda doğrulanmadı. iOS Windows'ta derlenmedi.

ZIP'teki `SHA256SUMS.txt` paket içeriğinin kaynak dosyalarla eşleştiğini doğrulamak içindir.
