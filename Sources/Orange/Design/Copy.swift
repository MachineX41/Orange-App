import OrangeKit
import SwiftUI

enum Copy {
    static func s(_ en: String, _ tr: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("tr") == true ? tr : en
    }

    static var fileStudio: String { s("File Studio", "Dosya Stüdyosu") }
    static var home: String { s("Home", "Ana sayfa") }
    static var library: String { s("Library", "Kitaplık") }
    static var tools: String { s("Tools", "Araçlar") }
    static var settings: String { s("Settings", "Ayarlar") }
    static var open: String { s("Open Orange", "Orange’u aç") }
    static var quit: String { s("Quit Orange", "Orange’dan çık") }
    static var openFiles: String { s("Choose Files…", "Dosya seç…") }
    static var sample: String { s("Use a sample image", "Örnek görselle dene") }
    static var headlineLead: String { s("One motion.", "Tek hareket.") }
    static var headlineAccent: String { s("A new copy, beside the original.", "Orijinalin yanında yeni bir kopya.") }
    static var subhead: String {
        s(
            "Convert, crop, and pack files on this Mac. Nothing is uploaded.",
            "Dönüştürme, kırpma ve arşiv bu Mac’te kalır. Hiçbir dosya yüklenmez."
        )
    }
    static var dropTitle: String { s("Drop files here", "Dosyaları buraya bırakın") }
    static var dropDetail: String { s("or choose them from disk", "ya da diskten seçin") }
    static var dropActive: String { s("Release to add", "Bırakınca eklenir") }
    static var selection: String { s("Selected", "Seçilenler") }
    static var clear: String { s("Clear", "Temizle") }
    static var convert: String { s("Convert", "Dönüştür") }
    static var actions: String { s("Actions", "İşlemler") }
    static var recent: String { s("Fresh copies", "Yeni kopyalar") }
    static var shelf: String { s("Float shelf", "Yüzen raf") }
    static var shelfHint: String { s("Kept here until you remove them.", "Siz kaldırana kadar burada durur.") }
    static var working: String { s("Working locally…", "Yerelde çalışıyor…") }
    static var emptyLibrary: String { s("Finished work will land here.", "Bitmiş işler burada görünür.") }
    static var search: String { s("Search library", "Kitaplıkta ara") }
    static var ready: String { s("Ready", "Hazır") }
    static var planned: String { s("Next", "Sırada") }
    static var toolsLead: String { s("What Orange can do today.", "Orange’un bugün yaptıkları.") }
    static var toolsSub: String {
        s(
            "Ready tools run on this Mac. The next set is mapped, not pretended.",
            "Hazır araçlar bu Mac’te çalışır. Sıradakiler haritada durur; varmış gibi davranmaz."
        )
    }
    static var noSharedFormat: String {
        s("These files don’t share a format.", "Bu dosyaların ortak bir formatı yok.")
    }
    static var needOneImage: String { s("Select a single image.", "Tek bir görsel seçin.") }
    static var needImages: String { s("Select one or more images.", "Bir veya daha fazla görsel seçin.") }
    static var needTwoPDFs: String { s("Select at least two PDFs.", "En az iki PDF seçin.") }
    static var needOnePDF: String { s("Select a single PDF.", "Tek bir PDF seçin.") }
    static var airDropUnavailable: String { s("AirDrop isn’t available for this selection.", "AirDrop bu seçim için kullanılamıyor.") }
    static var chooseFolder: String { s("Choose", "Seç") }
    static var moveTitle: String { s("Move to…", "Şuraya taşı…") }
    static var interrupted: String { s("Interrupted", "Yarıda kaldı") }
    static var reveal: String { s("Show in Finder", "Finder’da göster") }
    static var cancel: String { s("Cancel", "Vazgeç") }
    static var saveCopy: String { s("Save copy", "Kopyayı kaydet") }
    static var apply: String { s("Apply", "Uygula") }
    static var appearance: String { s("Appearance", "Görünüm") }
    static var revealDone: String { s("Reveal finished files in Finder", "Bitince Finder’da göster") }
    static var sound: String { s("Play a sound when work finishes", "İş bitince ses çal") }
    static var haptic: String { s("Haptic feedback on the wheel", "Çarkta dokunsal geri bildirim") }
    static var quality: String { s("JPEG quality", "JPEG kalitesi") }
    static var wheelHelp: String { s("← → select   Return applies   Esc closes", "← → seçer   Return uygular   Esc kapatır") }
    static var monitorOff: String {
        s(
            "Finder drag needs Accessibility access for Orange. In-app drop, the wheel, and tools already work.",
            "Finder sürüklemesi için Orange’a Erişilebilirlik izni gerekir. Pencereye bırakma, çark ve araçlar çalışır."
        )
    }
    static var about: String {
        s(
            "Orange is an independent file studio. It is not affiliated with Tangerine, LEAP STUDIO, or Nashi.",
            "Orange bağımsız bir dosya stüdyosudur. Tangerine, LEAP STUDIO veya Nashi ile bağlantılı değildir."
        )
    }
    static var legendShift: String { s("Shift + drag", "Shift + sürükle") }
    static var legendCommand: String { s("Command + drag", "Command + sürükle") }
    static var legendControl: String { s("Control + drag", "Control + sürükle") }
    static var legendConvert: String { s("Conversion wheel in Finder", "Finder’da dönüştürme çarkı") }
    static var legendTools: String { s("Tools for that file", "Dosyaya uygun araçlar") }
    static var legendActions: String { s("Float, copy, move, AirDrop", "Raf, kopyala, taşı, AirDrop") }
    static var files: String { s("files", "dosya") }
    static var close: String { s("Close", "Kapat") }
    static var remove: String { s("Remove", "Kaldır") }
    static var lockAspect: String { s("Lock aspect", "Oranı kilitle") }
    static var width: String { s("Width", "Genişlik") }
    static var height: String { s("Height", "Yükseklik") }
    static var format: String { s("Format", "Format") }
    static var pages: String { s("Pages", "Sayfalar") }
    static var pageHint: String { s("1-3, 5  or  all", "1-3, 5  veya  hepsi") }
    static var cropHint: String { s("Drag to select. Shift locks a square.", "Sürükleyerek seçin. Shift kareyi kilitler.") }
    static var rotateLeft: String { s("Left", "Sola") }
    static var rotateRight: String { s("Right", "Sağa") }
    static var flip: String { s("Flip", "Yansıt") }
    static var straight: String { s("180°", "180°") }

    static func converting(_ target: ConvertTarget) -> String {
        s("Converting to \(targetTitle(target))…", "\(targetTitle(target)) olarak dönüşüyor…")
    }

    static func count(_ value: Int) -> String {
        s("\(value) files", "\(value) dosya")
    }

    static func appearanceName(_ choice: AppearanceChoice) -> String {
        switch choice {
        case .system: s("System", "Sistem")
        case .light: s("Light", "Açık")
        case .dark: s("Dark", "Koyu")
        }
    }

    static func targetTitle(_ target: ConvertTarget) -> String {
        switch target {
        case .jpeg: "JPG"
        case .png: "PNG"
        case .webp: "WEBP"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        case .gif: "GIF"
        case .pdf: "PDF"
        case .mp4: "MP4"
        case .mov: "MOV"
        case .m4a: "M4A"
        }
    }

    static func toolTitle(_ tool: ToolID) -> String {
        switch tool {
        case .convert: s("Convert", "Dönüştür")
        case .compress: s("Compress", "Sıkıştır")
        case .resize: s("Resize", "Boyutlandır")
        case .crop: s("Crop", "Kırp")
        case .rotate: s("Rotate & flip", "Döndür ve yansıt")
        case .stripMetadata: s("Strip metadata", "Metadata’yı kaldır")
        case .imagesToPDF: s("Images to PDF", "Görsellerden PDF")
        case .mergePDF: s("Merge PDFs", "PDF birleştir")
        case .splitPDF: s("Split PDF", "PDF böl")
        case .archive: s("Zip & unzip", "Zip aç ve oluştur")
        }
    }

    static func toolSummary(_ tool: ToolID) -> String {
        switch tool {
        case .convert: s("Pick a format on the wheel. The original stays put.", "Çarktan format seçin. Orijinal yerinde kalır.")
        case .compress: s("Write a smaller JPEG copy with a quality you can see.", "Görebileceğiniz bir kaliteyle daha küçük bir JPEG kopyası.")
        case .resize: s("Set the exact pixel size of a new copy.", "Yeni kopyanın piksel boyutunu belirleyin.")
        case .crop: s("Drag a region. Shift locks the aspect.", "Bir alan sürükleyin. Shift oranı kilitler.")
        case .rotate: s("Quarter turns and a horizontal flip.", "Çeyrek dönüşler ve yatay yansıtma.")
        case .stripMetadata: s("Re-encode without carrying metadata forward.", "Metadata’yı taşımadan yeniden kodla.")
        case .imagesToPDF: s("Stack the selected images into one PDF.", "Seçili görselleri tek bir PDF’te toplayın.")
        case .mergePDF: s("Join PDFs in the order you selected.", "PDF’leri seçtiğiniz sırayla birleştirin.")
        case .splitPDF: s("Export page ranges as separate copies.", "Sayfa aralıklarını ayrı kopyalar olarak çıkarın.")
        case .archive: s("Zip files, or unpack a zip into a new folder.", "Dosyaları zipleyin ya da zip’i yeni klasöre açın.")
        }
    }

    static func plannedTitle(_ tool: PlannedTool) -> String {
        switch tool {
        case .video: s("Video bench", "Video tezgahı")
        case .audio: s("Audio bench", "Ses tezgahı")
        case .annotate: s("Annotate & redact", "İşaretle ve gizle")
        case .qr: s("Read QR", "QR oku")
        case .download: s("Link download", "Linkten indir")
        case .collage: s("Collage", "Kolaj")
        }
    }

    static func plannedSummary(_ tool: PlannedTool) -> String {
        switch tool {
        case .video: s("Trim, crop, speed, split, join, and stills.", "Kırpma, hız, bölme, birleştirme ve kare alma.")
        case .audio: s("Trim, loudness, channels, and bleep.", "Kırpma, ses yüksekliği, kanallar ve bleep.")
        case .annotate: s("Draw, type, and cover regions before sharing.", "Paylaşmadan önce çizin, yazın, bölge kapatın.")
        case .qr: s("Scan codes in images and PDF pages.", "Görsel ve PDF sayfalarındaki kodları okuyun.")
        case .download: s("Turn a public media link into a local file.", "Herkese açık bir medya linkini dosyaya çevirin.")
        case .collage: s("Arrange several images on one canvas.", "Birden fazla görseli tek tuvalde toplayın.")
        }
    }

    static func actionTitle(_ action: ActionID) -> String {
        switch action {
        case .float: s("Float", "Rafa al")
        case .copy: s("Copy", "Kopyala")
        case .move: s("Move", "Taşı")
        case .copyPath: s("Copy path", "Yolu kopyala")
        case .duplicate: s("Duplicate", "Çoğalt")
        case .reveal: s("Reveal", "Göster")
        case .airDrop: s("AirDrop", "AirDrop")
        case .zip: s("Zip", "Zip")
        }
    }

    static func modeTitle(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: s("Convert", "Dönüştür")
        case .tools: s("Tools", "Araçlar")
        case .actions: s("Actions", "İşlemler")
        }
    }

    static func symbol(for target: ConvertTarget) -> String {
        switch target {
        case .jpeg, .png, .heic, .bmp, .webp, .tiff: "photo"
        case .gif: "film"
        case .pdf: "doc.richtext"
        case .mp4, .mov: "film"
        case .m4a: "waveform"
        }
    }

    static func symbol(for tool: ToolID) -> String {
        switch tool {
        case .convert: "dial.medium"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .crop: "crop"
        case .rotate: "rotate.right"
        case .stripMetadata: "tag.slash"
        case .imagesToPDF: "photo.on.rectangle.angled"
        case .mergePDF: "square.stack"
        case .splitPDF: "rectangle.split.3x1"
        case .archive: "archivebox"
        }
    }

    static func symbol(for tool: PlannedTool) -> String {
        switch tool {
        case .video: "video"
        case .audio: "waveform"
        case .annotate: "pencil.and.outline"
        case .qr: "qrcode"
        case .download: "link"
        case .collage: "square.grid.3x3"
        }
    }

    static func symbol(for action: ActionID) -> String {
        switch action {
        case .float: "square.stack.3d.up"
        case .copy: "doc.on.doc"
        case .move: "folder"
        case .copyPath: "link"
        case .duplicate: "plus.square.on.square"
        case .reveal: "magnifyingglass"
        case .airDrop: "antenna.radiowaves.left.and.right"
        case .zip: "archivebox"
        }
    }
}
