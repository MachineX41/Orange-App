# Orange

Mac için yerel dosya stüdyosu. Bir dosyayı sürüklerken Shift, Command veya Control’e basın; ekranda Liquid Glass bir çark açılır. Çark açıldığı yerde sabit kalır, dosyayı istediğiniz dilime bırakırsınız ve yeni kopya orijinalin yanında oluşur.

Orange bağımsız bir uygulamadır. Tangerine, LEAP STUDIO veya Nashi ile bağlantılı değildir.

## Çalıştırma

macOS 26 veya üzeri, Xcode 26+ (Swift 6.2+).

```bash
swift test
scripts/build-app.sh
open build/Orange.app
```

Geliştirme derlemesi: `scripts/build-app.sh --debug`

## Çark

| Kısayol | Çark |
| --- | --- |
| ⇧ + sürükle | Dönüştür |
| ⌘ + sürükle | Araçlar |
| ⌃ + sürükle | Dosya işlemleri |

Finder, masaüstü veya herhangi bir uygulamadan sürüklerken çalışır ve Erişilebilirlik izni gerektirmez. Sürükleme sırasında tuşu değiştirirseniz çark yerinde kalır, yalnızca içeriği değişir. Uygulama içinde dosyaya tıklayınca da aynı çark açılır; ok tuşları seçer, Return uygular, Esc kapatır.

## Dönüştürme

- Görsel: JPG, PNG, HEIC, WEBP, AVIF, TIFF, BMP, GIF, PDF
- Belge: PDF, TXT, DOCX, RTF, HTML, ODT, Markdown girişi
- Video: MP4, MOV, M4V, GIF
- Ses: M4A, WAV, AIFF; videodan ses çıkarma

## Araçlar

- Görsel: fotoğraf düzenleme (ışık, renk, detay), kırpma ve döndürme, boyutlandırma, sıkıştırma, işaretleme, yüz ve metin algılamalı gizleme, arka plan ekleme, arka plan kaldırma, kolaj, görsellerden PDF
- PDF: birleştirme, bölme, sayfaları düzenleme (sürükle bırak sıralama, döndürme, silme), sıkıştırma
- Video: kesme (video veya GIF), kırpma, hız, sessize alma, kare çıkarma, bölme, bölge gizleme, birleştirme, sıkıştırma
- Ses: kesme (sessiz uçları otomatik kırpma), seviye ve normalleştirme, mono/stereo, bip ile sansürleme, sesten görselleştiricili video
- Diğer: metadata görüntüleme ve temizleme, QR ve barkod okuma, zip açma, link indirme (`yt-dlp` kuruluysa)

Her editör kendi penceresinde açılır. İşler arka planda çalışır, ilerleme sağ üstte görünür ve bitince sonuç Finder’da gösterilebilir.

## Proje yapısı

```
Sources/
  OrangeKit/        Arayüzden bağımsız motor (test edilir)
    Model/          Katalog ve dönüştürme yönlendirici
    Image/ PDF/ Document/ Media/ Vision/ Metadata/ Download/ IO/
  Orange/           SwiftUI uygulaması
    App/            Yaşam döngüsü, çalışma zamanı, modeller
    Design/         Tema ve metinler
    Features/       Wheel, Editors, Activity, Home, Library, Tools, Download, Settings, Shell
Tests/OrangeKitTests
scripts/build-app.sh
```
