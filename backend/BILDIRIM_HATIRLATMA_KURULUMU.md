# Bildirim, muayene hatırlatması ve abonelik paneli

3 Ekim 2026 • Uygulama 1.0.1+71

## Düzeltilen davranış

- Muayene/sigorta tarihi geçmişse kırmızı **X gün geçti**, bugünse **Bugün son gün**, 15 gün içindeyse sarı, daha uzaktaysa yeşil görünür. Tarih yoksa gri gösterilir. Türkiye takvim günü kullanılır; gece yarısı ve uygulamaya dönüşte ekran güncellenir.
- Eskiden gecikmiş araçların bildirimleri iptal ediliyordu. Yeni sunucu işçisi uygulama kapalıyken de muayene ve sigorta kayıtlarını tarar. 15/7/3 gün kala, son gün ve gecikme dönemlerinde bildirim üretir. İşçi ilk kez kurulduğunda mevcut gecikmiş kayıtları da bulur. Aynı tarih/aşama için tekrar bildirim oluşturmaz; gecikme sürerse haftalık hatırlatır.
- Tarih yenilenmiş, araç silinmiş veya sahibi değişmişse kuyruktaki eski hatırlatma gönderilmez. Hatırlatmalar bildirim geçmişine de yazılır.
- Usta teklifleri, parça teklifleri, mesajlar ve kiralama teklif/eşleşme hareketleri kalıcı gönderim kuyruğunu kullanır. İşlem geri alınırsa kiralama bildirimi de geri alınır. Toplu gönderimler 2.000 kişilik parçalara ayrılır; kalan kullanıcılar atlanmaz.
- Yeni kayıt, normal giriş ve sosyal giriş sonrasında OneSignal external ID oturumdaki kullanıcıyla eşitlenir.
- Profil → **Aboneliklerim**: Premium garaj, Usta/Rent A Car üyeliği ve OBD erişiminin aktifliği, ücretsiz deneme, kalan gün ve erişim bitişi gösterilir. Bilgi sunucunun doğrulanmış erişim kaydından gelir. Mağaza yenilemesi henüz kayda yansımadıysa paket detayında **Satın alımları geri yükle** kullanılmalıdır.

## Sunucuya yükleme

1. Mevcut PHP dosyaları ve veritabanını yedekleyin. Yeni backend ZIP'inin içeriğini `api.php` ile aynı dizine birlikte yükleyin: `/www/wwwroot/eliteagency.sbs/`. Dosyaları ayrıca `lib/` altına taşımayın.
2. Mevcut `.env`, yüklenen fotoğraflar ve veritabanını koruyun. ZIP gerçek `.env` veya gizli anahtar içermez. `.env.example` bir şablondur; mevcut dosyanızın üzerine yazılmamalıdır.
3. Sunucudaki PHP'de PDO MySQL ve cURL etkin olmalı; veritabanı hesabının yeni kuyruk/hatırlatma tablolarını oluşturma yetkisi olmalı. API açılışı veya işçi ilk çalıştırması eksik tabloları oluşturur.
4. aaPanel → Zamanlanmış Görevler bölümünde **her dakika** çalışacak Shell görevi ekleyin. Sunucunuzdaki gerçek PHP CLI yolunu kullanın:

   ```sh
   php /www/wwwroot/eliteagency.sbs/notification-worker.php
   ```

5. Sürüm güncelleme duyuruları için ayrı mevcut işçiyi de her dakika çalıştırın:

   ```sh
   php /www/wwwroot/eliteagency.sbs/app-update-worker.php
   ```

6. OPcache kullanılıyorsa yeni dosyalar için PHP hizmetini yeniden başlatın. `nginx-protect.conf.example` yardımcılar, `.env` ve işçi dosyalarının HTTP erişimini engelleyen örnek kuralları içerir; mevcut eşdeğer kurallarla çakıştırmayın.
7. Admin → Güncellemeler → **Telefon bildirimleri ve hatırlatmalar** alanında işçinin çalıştığını kontrol edin. Bu alan son yedi gündeki bekleyen, servisçe kabul edilen, başarısız ve uygun cihaz bulunmayan gönderimleri gösterir. İlk işçi çalıştırmasından önce görev çalışmıyor uyarısı normaldir.

Hatırlatma taraması Türkiye saatiyle 09.00 sonrasındaki ilk görevde günde bir kez yapılır. İlk kurulum 09.00 sonrasındaysa ilk çalıştırmada tarar. Kuyruk her dakika işlenir. PHP-FPM kullanıldığında yeni işlem bildirimleri yanıt tamamlandıktan sonra hemen de denenir. Başarısız gönderimler artan beklemeyle ve servis `Retry-After` süresine uyarak en fazla 8 kez/24 saat denenir. Aynı bildirimin tekrarlarında aynı idempotency anahtarı kullanılır. Servise ulaşmış bildirim telefondan geri çekilemez.

## Gönderdiğiniz ENV metni hakkında

`ALLOWED_ORIGINS` satırı Markdown bağlantısı yerine düz metin olmalıdır:

```dotenv
ALLOWED_ORIGINS="https://eliteagency.sbs,https://www.eliteagency.sbs,http://localhost:*,http://127.0.0.1:*"
```

Satırların sonunda sohbet biçimlendirmesinden gelen `\`, `\#` veya `&#x20;` parçalarını dosyaya koymayın. Güncellenmiş parser eşleşen Markdown köken listesini güvenli biçimde okuyabilir; diğer ayarların doğru düz metin olması gerekir. Parolaların gerçek içeriğini rastgele değiştirmeyin.

`PUSHER_APP_ID`, `PUSHER_KEY`, `PUSHER_SECRET` aynı Pusher uygulamasına ait olmalı. Şablondaki App ID, verdiğiniz ID ile güncellendi; canlı servis hesabı doğrulanmadı. OneSignal App ID/App API key aynı uygulamaya, bu uygulamadaki FCM ve APNs ayarları da doğru Android/iOS projesine bağlı olmalı. HTTP 401/403 görülürse ilgili servis anahtarı/yetkisi kontrol edilmeli. Alanın dolu olması anahtarın geçerli olduğunu kanıtlamaz.

Paylaştığınız DB parolası ve servis sırları sohbet içinde açığa çıktığı için bunları sağlayıcı panellerinden yenileyin ve yeni değerleri yalnızca sunucudaki `.env` dosyasına koyun. JWT sırrı değişirse mevcut oturumlar yeniden giriş gerektirir. Bu çalışma sırasında gerçek sırlar koda veya teslim ZIP'lerine eklenmedi.

## Telefonlarda doğrulama

- OneSignal'da Android için FCM, iOS için APNs yapılandırılmalı. Kullanıcı uygulamaya giriş yapmış ve bildirim izni vermiş olmalı. Bildirim izni kapalı, çevrimdışı veya işletim sistemince kısıtlanan cihazlarda kesin teslim garanti edilmez.
- Bir test müşterisinin muayene tarihini dün olarak kaydedin: panel **1 gün geçti** ve kırmızı göstermeli. İşçi taramasından sonra uygulama içi bildirim kaydı oluşmalı; uygun cihaz varsa OneSignal gönderimi kabul etmeli. İşçiyi tekrar çalıştırmak aynı aşamayı çoğaltmamalı.
- Tarihi geleceğe güncellediğinizde kırmızı durum kalkmalı; henüz gönderilmemiş eski hatırlatma iptal edilmeli.
- İki test hesabıyla usta teklifi, Rent A Car karşı teklif/kabul ve parça teklifi gönderin. Uygulama önde, arkada ve kapalı durumlarda gerçek telefonlarda kontrol edin.
- Google girişinde Play App Signing sertifikasının SHA-1/SHA-256 değerleri Google/Firebase projesinde kayıtlı olmalı. Yerel yükleme anahtarı ile Google Play dağıtım sertifikası farklı olabilir.
- iPhone'da Sign in with Apple yeteneği ve `com.oto.tag` App ID/provisioning eşleşmeli. Apple ikinci girişte isim/e-posta vermeyebilir; sunucu kimlikte `sub` alanını esas alır. Web Apple girişi için ayrıca gerçek Service ID ve dönüş adresi gerekir; şablonda bunlar uydurulmadı.
- Google satın alma doğrulaması için `GOOGLE_SERVICE_ACCOUNT_PATH` ile Play yetkili servis hesabı, Apple makbuz doğrulaması için doğru `APPLE_SHARED_SECRET` gerekir. Gerçek mağaza/sandbox satın alımı burada yapılmadı.

Kaynaklar: [OneSignal push API](https://documentation.onesignal.com/reference/push-notification), [OneSignal tekrar gönderim koruması](https://documentation.onesignal.com/reference/idempotent-notification-requests), [Flutter desteklenen platformlar](https://docs.flutter.dev/reference/supported-platforms).
