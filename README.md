# Orange

Mac için yerel dosya stüdyosu. Dosyayı bırakın, çarktan formatı veya aracı seçin, yeni kopya orijinalin yanında oluşsun.

Orange bağımsız bir uygulamadır. Tangerine, LEAP STUDIO veya Nashi ile bağlantılı değildir.

## Çalıştırma

macOS 14 veya üzeri, Swift 6.

```bash
swift test
scripts/build-app.sh
open build/Orange.app
```

Geliştirme derlemesi: `scripts/build-app.sh --debug`

## Bu sürümde çalışanlar

- Ana sayfa, kitaplık ve araç kataloğu
- Görsel dönüştürme: JPG, PNG, WEBP, HEIC, TIFF, BMP, GIF, PDF
- Sıkıştırma, boyutlandırma, kırpma, döndürme, metadata’sız yeniden kodlama
- Görsellerden PDF, PDF birleştirme ve sayfa aralığıyla bölme
- Zip oluşturma ve güvenli açma
- Finder’da Shift, Command veya Control ile sürüklerken çark
- Dosya işlemleri: raf, kopyala, taşı, yolu kopyala, çoğalt, göster, AirDrop, zip
- AVFoundation ile okunabilen videolar için MP4/MOV, ses için M4A
- Sistem, açık ve koyu görünüm

Video tezgahı, ses tezgahı, işaretleme, QR, link indirme ve kolaj katalogda “Sırada” olarak durur. Bu sürüm onları çalışıyormuş gibi göstermez.

## Kısayollar

| Kısayol | İşlem |
| --- | --- |
| ⌘O | Dosya seç |
| ⌘1 / ⌘2 / ⌘3 | Ana sayfa, kitaplık, araçlar |
| ⇧ sürükle | Dönüştürme çarkı |
| ⌘ sürükle | Araç çarkı |
| ⌃ sürükle | Dosya işlemleri çarkı |

Çark açıkken ok tuşları seçer, Return uygular, Esc kapatır. Kırpmada Shift kareyi kilitler.

Finder çarkı görünmezse Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik içinden Orange’a izin verin. Pencereye bırakma ve araçlar bu izin olmadan da çalışır.
