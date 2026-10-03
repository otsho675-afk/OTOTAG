# Usta / müşteri eşleşmesi güncellemesi

## Değişiklikler
- Usta haritasının başlangıç arama alanı 10 km yerine, sunucunun duyuru alanıyla uyumlu 50 km. Kaydırıcıyla daraltılabilir.
- Konum izni kapalı, konum bulunamıyor, HTTP hatası, geçersiz sunucu yanıtı, üyelik veya kota kısıtı artık boş talep listesi gibi görünmez; açıklama ve yeniden deneme gösterilir.
- İlk konum isteği yüksek doğrulukla 15 saniyeye kadar bekler. İzin kontrolünün aynı anda iki kez başlaması engellenir; kalıcı izin reddi ele alınır.
- Çevrimdışı duruma geçildikten veya ekran kapandıktan sonra gelen talep yanıtı kart açmaz.
- Müşteri arama ekranında radar animasyonu. Teklif geldiğinde, hata olduğunda, uygulama arka plana geçtiğinde, görünür ekran değiştiğinde veya hareket azaltma ayarı açıkken tekrarlanan çizim durur. Yalnızca küçük radar alanı yeniden çizilir.
- Bu değişiklikler için ek animasyon paketi veya görsel indirme yoktur.

## Kurulum
ZIP içindeki `lib` klasörünü mevcut Flutter projesinin köküne birleştirin. Sunucudaki PHP klasörüne yüklemeyin.
Chrome testini hot restart ile yeniden başlatın. iPhone için güncellenmiş kaynaklardan yeni Codemagic derlemesi oluşturup yeni TestFlight derlemesini yükleyin; eski derlemeyi yeniden yüklemek değişiklikleri getirmez.
Bu pakette yeni bir PHP veya veritabanı değişikliği yoktur.

## Doğrulama
`flutter test test/provider_job_feed_test.dart test/matching_radar_test.dart test/service_matching_test.dart test/app_motion_test.dart`

Testler HTTP hataları/üyelik kısıtları, bozuk cevaplar, teklif onayı, kayıp yanıt sonrası durum kurtarma, dar ekran/büyük yazı ve animasyon yaşam döngüsünü kapsar.

## Canlı doğrulama sınırı
Kullanıcı 53 usta, 45 müşteri. Sağlanan eski SQL yedeğinde ikisi de Konya'da aktif ve 53 tamirci; 45'in yedekteki talepleri iptal edilmiş. Bu yedek, son canlı denemenin sonucunu kanıtlamaz.
Canlı SSH erişimi kimlik doğrulaması nedeniyle açılamadı. iPhone–Chrome üzerinde yeni talep, teklif ve kabul akışı canlı olarak doğrulanmadı.
`matching-check-53-45.sql` salt okunur teşhis sorgusudur. Açık talep sırasında phpMyAdmin'de çalıştırın. Chrome'da konum izni açık, usta çevrimiçi olmalı; müşteri Tamirci seçmeli. Mevcut eşleşme varsa önce onun durumu incelenmeli, kayıtlar elle silinmemeli.
