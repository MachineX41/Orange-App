# Gizlilik Bildirimi

**Yürürlük tarihi:** 31 Ekim 2026 · **Sürüm:** 1

Orange, Mac’inizde çalışan bir dosya stüdyosudur. Bu bildirim, uygulamanın hangi verilere eriştiğini, neyi nerede sakladığını ve ağa ne zaman çıktığını açıklar. Kısaca: **dosyalarınız Mac’inizden çıkmaz ve Orange sizinle ilgili hiçbir veri toplamaz.**

## 1. Toplamadığımız veriler

- Hesap, e‑posta, ad veya iletişim bilgisi istemeyiz.
- Analiz, telemetri, reklam, çökme raporu veya takip SDK’sı yoktur.
- Dosyalarınız, içerikleri ve meta verileri hiçbir sunucuya gönderilmez.
- Kişisel verileriniz üçüncü taraflarla paylaşılmaz veya satılmaz.

## 2. Mac’inizde işlenen veriler

Tüm dönüştürme, düzenleme ve analiz işlemleri macOS çerçeveleriyle (Core Image, Vision, AVFoundation, PDFKit vb.) **yalnızca cihazınızda** yapılır. Yüz ve metin algılama gibi özellikler de çevrimdışı çalışır.

Orange yalnızca kendi çalışması için aşağıdakileri Mac’inizde saklar:

| Veri | Konum | Amaç |
| --- | --- | --- |
| Tercihler (tema, çark, kalite, onay tarihi) | `~/Library/Preferences/app.orange.studio.plist` | Ayarlarınızı hatırlamak |
| İş geçmişi ve raf listesi (dosya yolları) | `~/Library/Application Support/Orange/library.json` | Kitaplık ve Raf ekranları |
| Örnek dosyalar | `~/Library/Application Support/Orange/` | “Örnek Dene” özelliği |

Geçmişi ve rafı istediğiniz an **Ayarlar › Gizlilik › Geçmişi ve Rafı Temizle** ile silebilirsiniz; bu işlem dosyalarınıza dokunmaz. Uygulamayı kaldırıp yukarıdaki dosyaları silerseniz Orange’a ait hiçbir veri kalmaz.

## 3. İzinler

Orange yalnızca ihtiyaç duyduğu izinleri, gerektiğinde ister. Tüm izinler macOS tarafından yönetilir ve **Sistem Ayarları › Gizlilik ve Güvenlik** bölümünden istediğiniz an geri alınabilir.

- **Masaüstü, Belgeler, İndirilenler:** Sonuçları orijinal dosyanın yanına kaydedebilmek için. Reddederseniz Orange çalışmaya devam eder; yalnızca bu klasörlere yazamaz.
- **Çıkarılabilir ve ağ birimleri:** Yalnızca bu birimlerdeki bir dosyayla çalıştığınızda.
- **Girişte açılma (isteğe bağlı):** Yalnızca siz açarsanız, macOS’un Giriş Öğeleri mekanizmasıyla.

Sürükleme çarkı, macOS sürükleme panosunu ve değiştirici tuşların durumunu okur. Orange **Erişilebilirlik, Ekran Kaydı, Giriş İzleme, Kamera, Mikrofon, Kişiler veya Konum** izni istemez ve tuş vuruşlarınızı kaydetmez.

## 4. Ağ bağlantıları

Orange arka planda ağa bağlanmaz. Tek istisna, **İndir** ekranına kendinizin yapıştırdığı bir bağlantıdır:

- Bağlantı doğrudan bir dosyaysa Orange onu o siteden indirir.
- Video sitelerinde, Mac’inizde kuruluysa, bağımsız açık kaynak araç **yt‑dlp** çalıştırılır. yt‑dlp, Orange’ın parçası değildir; kendi lisansına ve davranışına tabidir.

Bu bağlantılarda yalnızca ilgili site ile Mac’iniz arasında, standart bir indirmede olduğu gibi veri alışverişi olur (IP adresiniz ve istek bilgileri o sitenin politikasına tabidir). Orange bu istekleri kendi sunucusu üzerinden geçirmez; böyle bir sunucusu yoktur.

Yardım menüsündeki bağlantılar (bu belge, Kullanım Koşulları, GitHub) varsayılan tarayıcınızda açılır.

## 5. Çocuklar

Orange çocuklara yönelik değildir ve kimseden bilerek kişisel veri toplamaz.

## 6. Haklarınız (KVKK ve GDPR)

Orange sizinle ilgili kişisel veri işlemediği ve aktarmadığı için, 6698 sayılı KVKK veya GDPR kapsamında tarafımızca tutulan bir kaydınız bulunmaz. Mac’inizdeki yerel verileri yukarıda anlatıldığı gibi kendiniz görüntüleyebilir ve silebilirsiniz.

## 7. Değişiklikler

Bu bildirim değişirse sürüm numarası artırılır ve Orange ilk açılışta yeni metni yeniden onayınıza sunar.

## 8. İletişim

Sorularınız için [GitHub Issues](https://github.com/MachineX41/Orange-App/issues) üzerinden bize ulaşabilirsiniz.

---

## Privacy Notice (English summary)

Orange processes everything on your Mac. It has no accounts, analytics, telemetry, ads or tracking, and never uploads your files. It stores only your preferences and a local list of recent jobs and shelf items (`~/Library/Application Support/Orange/library.json`), which you can clear in **Settings › Privacy**. It asks only for Desktop, Documents and Downloads folder access (to save results next to originals) and, optionally, to open at login. It never asks for Accessibility, Screen Recording, Input Monitoring, Camera, Microphone, Contacts or Location. Network access happens only when you paste a link on the **Download** screen; Orange then fetches it directly or runs your locally installed, independent `yt-dlp`. Questions: [GitHub Issues](https://github.com/MachineX41/Orange-App/issues).
