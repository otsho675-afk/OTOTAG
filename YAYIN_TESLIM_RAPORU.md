# OTOTAG 1.0.1+71 — yayın teslim raporu

3 Ekim 2026

## Teslim

- `OTOTAG-1.0.1+71.aab`: mevcut yerel Android yükleme anahtarıyla imzalanmış Google Play paketi. Paket adı `com.oto.tag`, versionName `1.0.1`, versionCode `71`.
- `OTOTAG-1.0.1+71-source.zip`: güncel Flutter/Android/iOS/PHP kaynakları ve testler. Gerçek `.env`, `config.env`, keystore, parolalar, derleme önbelleği ve veritabanı dahil değildir.
- `OTOTAG-1.0.1+71-backend.zip`: birlikte yüklenmesi gereken PHP dosyaları, JWT yardımcıları, iki zamanlanmış görev ve kurulum notları. İçeriği `api.php` ile aynı klasöre yükleyin.
- `OTOTAG-1.0.1+71-web.zip`: son web üretim çıktısı. Mevcut web uygulamasının dağıtım klasörüne yükleyin; API'nin kökündeki başka siteyi bununla değiştirmeyin.
- `SHA256SUMS.txt`: teslim dosyalarının bütünlük özetleri.

Dosyalar proje içindeki `build/release-delivery/1.0.1+71/` klasöründedir. Bu çalışma sırasında canlı sunucuya, Google Play'e veya App Store'a yükleme yapılmadı.

## Yapılan değişiklikler

### Eşleşme doğruluğu

Usta teklifinde kullanıcının ekranda gördüğü tutar ve teklif revizyonu sunucuda doğrulanır. Fiyat değiştirilmişse eski ekran yeni fiyatı sessizce kabul edemez. İş, usta ve teklif kayıtları aynı işlemde kilitlenir; aynı işin iki ustaya veya aynı ustanın iki işe aynı anda eşleşmesi engellenir. İptal/kabul/ret yarışları, kendi teklifini kabul etme, uygun olmayan şehir/hizmet/mesafe ve üyelik durumları kontrol edilir.

Bağlantı kesilince istemci yazma isteğini körlemesine tekrarlamaz; sunucudan gerçek durum okunur. Gecikmiş okuma yeni işlem sonucunun üstüne yazamaz. Canlı olaylar doğrudan eşleşme ekranı açmak yerine doğrulanmış durumu yeniler. Mevcut kiralama kilitleri, fiyat/sürüm doğrulamaları, rezervasyon geçmişi ve yetki testleri korunur.

### Tasarım ve performans

Usta teklif ekranı daha kısa ve okunabilir kartlarla yeniden düzenlendi. Fiyat/süre sıralaması, açık teklif onayı, karşı teklif ve bağlantı hatası durumları eklendi. Değerlendirmesi olmayan ustaya sahte beş yıldız gösterilmez. Usta ve kiralama akışlarında kısa giriş/durum geçişleri vardır; hareket azaltma tercihi desteklenir. Kullanılmayan sürekli animasyonlar kaldırıldı. Örtülü veya arka plandaki ekranların gereksiz istekleri azaltıldı; aynı anda yenileme istekleri çakışmaz.

Admin panelindeki mobil/masaüstü gezinme, hızlı erişim, kiralama kontrolü ve Android/iPhone sürüm duyurusu yönetimi teslim kaynaklarına dahildir. Güncellemeler bölümüne bildirim kuyruğu ve zamanlanmış görev sağlığı da eklendi.

### Muayene, sigorta ve bildirimler

Yeşil tanımlanmış hata rengi düzeltildi. Muayene/sigorta/bakım gecikmesi kırmızı; yaklaşan tarih sarı gösterilir. Tarih hesabı Türkiye takvim günü üzerinden yapılır ve gece yarısında yenilenir. Tarihi geçmiş araçlarda bildirimleri iptal eden eski akış kaldırıldı.

Sunucu işçisi, uygulama kapalıyken de hatırlatma oluşturur; aynı aşamayı tekrar etmez. Yenilenmiş/silinmiş araç için bekleyen eski hatırlatma iptal edilir. Usta, kiralama, parça ve mesaj bildirimleri kalıcı kuyruğa alınır; geçici hatalar tekrar denenir. 2.000 kişiden büyük bildirim hedefleri bölünür; kullanıcılar atlanmaz. Yeni kayıtta da telefon bildirim kimliği oturumla eşleşir.

**Sunucuda iki işçinin kurulması gerekir.** Ayrıntılar ve aaPanel komutları: [Bildirim ve hatırlatma kurulumu](backend/BILDIRIM_HATIRLATMA_KURULUMU.md), [Admin sürüm duyurusu kurulumu](backend/ADMIN_GUNCELLEME_KURULUMU.md). Tek başına uygulama yüklemek sunucudaki zamanlanmış görevi oluşturmaz.

### Abonelik ve sosyal giriş

Profil → Aboneliklerim paneli; aktif paketleri, deneme hakkını, kalan günü, bitiş tarihini ve Rent A Car paketine dahil OBD erişimini gösterir. Sunucu hatasında eski bilgi doğrulanmış gibi gösterilmez. Yönetim, iptal ve satın alım geri yükleme mevcut mağaza akışına bağlıdır. Durum sunucuda son doğrulanmış mağaza bitiş tarihidir; otomatik yenileme kayda yansımadıysa geri yükleme gerekir.

Google/Apple girişinde paralel işlem başlatma engellendi, boş kimlik kanıtları reddedildi. Sunucu; imzayı, sağlayıcıyı, uygulama kimliğini ve token süresini kontrol eder. Apple'ın tekrar girişte ad/e-posta vermemesi yeni hesap sanılması için gerekçe değildir; kimlik `sub` ile doğrulanır. Mağaza/OAuth hesabı yapılandırmasının canlı doğrulaması bu yerel testlerin dışında kalır.

## Doğrulama sonuçları

| Kontrol | Sonuç |
|---|---|
| Flutter statik analiz | Hata, uyarı ve stil bildirimi yok |
| Flutter testleri | 170 başarılı |
| PHP/MySQL testleri | 607 başarılı kontrol |
| PHP dosyaları ve işçiler | Sözdizimi kontrolleri başarılı |
| Android release AAB | Başarıyla derlendi, JAR imzası doğrulandı |
| Bundletool | AAB yapısı doğrulandı |
| 64 bit yerel kütüphaneler | 8 kütüphanede 16 KB ELF yükleme bölümü hizalaması başarılı |
| Web release | Başarıyla derlendi |
| Git fark kontrolü | Boşluk hatası yok |

Backend kapsamı: 178 kiralama/itibar, 143 gerçek API giriş/yetki, 15 çalışma zamanı, 43 abonelik/sayfalama, 33 yükleme, 15 satın alma, 7 OAuth, 32 kimlik/yol yetkisi, 17 yapılandırma, 54 admin güncellemesi, 39 usta eşleşmesi, 31 bildirim/abonelik kontrolü. Eşzamanlı eşleşme senaryoları ayrı PHP süreçleri ve izole InnoDB veritabanlarında çalıştırıldı; üretim veritabanı kullanılmadı.

Arayüz testleri dar telefon/tablet/masaüstü genişliklerini, büyütülmüş yazıyı, azaltılmış hareketi, arka plana geçmeyi, bağlantı hatasını ve kaybolan işlem yanıtını kapsar. Bunlar gerçek cihazda FPS veya pil tüketimi ölçümü değildir.

Test günlükleri `build/release-audit/` içindedir. Backend testlerini çalıştırmak için `test/run_backend_tests.ps1` kullanılır; testler yalnızca `127.0.0.1:33307` üzerindeki adlandırılmış regresyon şemalarına yöneliktir.

## Mağaza ve cihaz sınırları

- Android paketi minimum **API 24 / Android 7**, hedef **API 36**; ARM 32 bit, ARM 64 bit ve x86_64 mimarilerini içerir. Kamera, mikrofon, dokunmatik ve GPS gereksinimleri isteğe bağlıdır. Flutter'ın gerekli OpenGL desteği korunur. Bu sürümlerin altındaki veya gerekli grafik yeteneği olmayan tüm cihazlara uyumluluk sözü verilemez. [Flutter platform desteği](https://docs.flutter.dev/reference/supported-platforms)
- iOS projesi ve Podfile minimum **iOS 15** olacak şekilde eşitlendi. Windows'ta iOS archive/IPA oluşturulamadı. Mac'te Xcode ile archive, signing, provisioning, privacy manifest doğrulaması ve TestFlight testi gerekir. Apple'ın 28 Nisan 2026 sonrası yüklemeleri için Xcode 26/iOS 26 SDK gereksinimi dikkate alınmalıdır. [Apple SDK gereksinimi](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)
- Android derlemesi mevcut eklentilerin gelecekteki Flutter sürümlerinde Built-in Kotlin'e geçiş ihtiyacına ilişkin uyarı veriyor; mevcut release derlemesi başarılıdır. SDK/eklenti sürümleri topluca ve test edilmeden değiştirilmedi.
- Jarsigner'ın kendinden imzalı Android yükleme sertifikası/zaman damgası ve ZIP okuma sırası uyarıları mevcut; imza doğrulaması ve bundletool doğrulaması başarılıdır. Play Console'daki yükleme sertifikası ve daha önce kullanılmış en yüksek versionCode burada doğrulanmadı. `71` zaten kullanıldıysa yeni derleme numarasıyla tekrar paket alınmalıdır.
- Bildirim izni, FCM/APNs, OneSignal anahtarları, Google SHA sertifikaları, Apple yetenekleri ve gerçek mağaza ürünleri hesap panellerinde doğrulanmalıdır. Canlı push gönderimi veya gerçek satın alma yapılmadı. Servisin gönderimi kabul etmesi her telefonun teslim alması demek değildir.
- Önceden mağazaya yüklediğiniz binary bu kaynak değişiklikleriyle kendiliğinden güncellenmez. Yeni arayüz, abonelik paneli ve güncelleme modalı için yeni mobil sürüm dağıtılmalıdır. Yeni backend mevcut endpointleri korur; eski istemcinin değiştirilmiş fiyatı onaylamasına izin verilmez. Eski mobil binary'nin tamamıyla canlı uyumluluk testi yapılmadı.
- Paylaşılan Flutter Web `ViewInsets` hata izi motorun debug boyut/klavye hesabındadır. Üretim web derlemesi başarılıdır; tarayıcı cihaz emülasyonunda aynı debug hatasının yeniden üretilmesi bu teslimde doğrulanmadı.

Kaynak ZIP'ini ayrı klasöre açıp yeniden derlerken mevcut özel `config.env` ve Android imzalama ayarlarınızı koruyun. Örnek istemci ayarı `config.env.example`, imzalama yönergesi `ANDROID_IMZALAMA.md` içindedir. Sunucu sırlarını Flutter'ın `config.env` dosyasına koymayın; bu dosya uygulama varlığı olarak dağıtılır.

Bu sonuçlar tespit edilen sorunların giderildiğini ve listelenen kontrollerin geçtiğini gösterir; sıfır hata veya mağaza onayı garantisi değildir. Yayın öncesi gerçek Android/iPhone üzerinde giriş, konum, arka plan bildirimi, ödeme ve eşleşmenin uçtan uca denenmesi gerekir.
