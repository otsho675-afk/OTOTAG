# Android release imzalama

`validateSigningRelease` hatasının nedeni `android/app/new-upload-keystore.jks` dosyasının bulunmamasıydı. Kotlin KGP ve Java 8 uyarıları bu hatanın nedeni değildir.

İmzalama artık kaynak kodundaki sabit şifreleri kullanmak yerine Git tarafından dışlanan `android/key.properties` dosyasından okunur. Kullanıcının sağladığı `new-upload-keystore.jks` dosyası mevcut alias ve her iki şifreyle doğrulandı, `android/app/new-upload-keystore.jks` konumuna kopyalandı ve ayara bağlandı. Yeni keystore oluşturulmadı; Downloads klasöründeki orijinal dosya korunur.

Bu bilgisayarda anahtar bağlıdır. AAB oluşturmak için proje kökünde PowerShell:

```powershell
flutter build appbundle --release
```

Başka bir bilgisayarda veya farklı mevcut anahtar dosyasına bağlanmak gerektiğinde:

```powershell
.\configure-android-signing.ps1
flutter build appbundle --release
```

Kurulum komutu mevcut dosyanın yolunu ve şifresini yerel terminalde ister. Şifre yazarken görünmez. Keystore'u açar, özel anahtar alias'ını bulur ve anahtarın açılabildiğini doğruladıktan sonra ayarı kaydeder. Yanlış dosya/şifrede mevcut ayarı değiştirmez. Şifreyi sohbete veya GitHub'a yazmayın.

`android/key.properties` ve `android/app/new-upload-keystore.jks` Git tarafından dışlanır. Yeni bir bilgisayarda bu yerel dosyalar ayrıca sağlanmalıdır. Debug keystore release anahtarının yerine kullanılmaz.

Manuel yapılandırma için `android/key.properties.example` biçimini kullanın. `storeFile` mutlak yol olabilir; Windows yolunda `/` kullanın. Göreli yol `android/app` klasörüne göre çözülür. Dosya, alias ve her iki şifre doğru olmalıdır.

CI ortamı aynı değerleri `OTOTAG_KEYSTORE_PATH`, `OTOTAG_STORE_PASSWORD`, `OTOTAG_KEY_ALIAS`, `OTOTAG_KEY_PASSWORD` ortam değişkenleriyle sağlayabilir; ortam değişkenleri yerel properties değerlerine göre önceliklidir. Keystore CI makinesinde de bulunmalıdır. Bu değişiklik iOS imzalama ayarını değiştirmez.

Çıktı: `build/app/outputs/bundle/release/app-release.aab`. Android debug ve release AAB derlemeleri başarılı. AAB imzası doğrulandı; sertifikası kullanıcının sağladığı yükleme anahtarıyla aynı. AAB içinde keystore veya key.properties bulunmadığı da kontrol edildi. Google Play Console'daki kayıtlı yükleme sertifikasıyla eşleşme, Console'a yükleme sırasında ayrıca doğrulanır.

Kotlin KGP/Java 8 uyarıları gelecekteki araç sürümleriyle ilgilidir; bu imzalama düzeltmesi onları gizlemez veya eklentileri yükseltmez. Backend dosyaları değişmedi; önceki backend ZIP'i geçerlidir.
