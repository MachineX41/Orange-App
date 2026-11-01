import OrangeKit
import SwiftUI

func L(_ english: String, _ turkish: String) -> String {
    Lang.t(english, turkish)
}

extension MediaKind {
    var title: String {
        switch self {
        case .image: L("Images", "Görseller")
        case .video: L("Video", "Video")
        case .audio: L("Audio", "Ses")
        case .pdf: "PDF"
        case .document: L("Documents", "Belgeler")
        case .archive: L("Archives", "Arşivler")
        case .other: L("Files", "Dosyalar")
        }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .document: "doc.text"
        case .archive: "archivebox"
        case .other: "doc"
        }
    }

    var tint: Color {
        switch self {
        case .image: Color(red: 0.98, green: 0.55, blue: 0.18)
        case .video: Color(red: 0.93, green: 0.30, blue: 0.36)
        case .audio: Color(red: 0.62, green: 0.38, blue: 0.95)
        case .pdf: Color(red: 0.92, green: 0.26, blue: 0.22)
        case .document: Color(red: 0.24, green: 0.52, blue: 0.96)
        case .archive: Color(red: 0.55, green: 0.48, blue: 0.40)
        case .other: .secondary
        }
    }

    static let toolKinds: [MediaKind] = [.image, .video, .audio, .pdf]
}

extension ConvertTarget {
    var title: String {
        switch self {
        case .jpeg: "JPG"
        case .txt: L("TEXT", "METİN")
        default: rawValue.uppercased()
        }
    }

    var symbol: String {
        switch self {
        case .jpeg, .png, .heic, .webp, .avif, .tiff, .bmp: "photo"
        case .gif: "photo.stack"
        case .pdf: "doc.richtext"
        case .txt: "text.alignleft"
        case .docx, .odt: "doc.text"
        case .rtf: "doc.plaintext"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .mp4, .mov, .m4v: "film"
        case .m4a, .wav, .aiff: "waveform"
        }
    }
}

extension ToolID {
    var title: String {
        switch self {
        case .adjustImage: L("Edit", "Düzenle")
        case .cropImage: L("Crop", "Kırp")
        case .compressImage: L("Compress", "Sıkıştır")
        case .annotateImage: L("Annotate", "İşaretle")
        case .redactImage: L("Redact", "Gizle")
        case .addBackground: L("Add BG", "Arka Plan")
        case .removeBackground: L("Remove BG", "BG Sil")
        case .resizeImage: L("Resize", "Boyutlandır")
        case .rotateImage: L("Rotate", "Döndür")
        case .collage: L("Collage", "Kolaj")
        case .imagesToPDF: L("Make PDF", "PDF Yap")
        case .mergePDF: L("Merge", "Birleştir")
        case .splitPDF: L("Split", "Böl")
        case .organizePDF: L("Organize", "Düzenle")
        case .compressPDF: L("Compress", "Sıkıştır")
        case .trimVideo: L("Trim", "Kes")
        case .cropVideo: L("Crop", "Kırp")
        case .compressVideo: L("Compress", "Sıkıştır")
        case .videoSpeed: L("Speed", "Hız")
        case .muteVideo: L("Mute", "Sessiz")
        case .videoFrames: L("Frames", "Kareler")
        case .splitVideo: L("Split", "Böl")
        case .redactVideo: L("Redact", "Gizle")
        case .joinVideos: L("Join", "Birleştir")
        case .trimAudio: L("Trim", "Kes")
        case .normalizeAudio: L("Level", "Seviye")
        case .audioChannels: L("Channels", "Kanallar")
        case .bleepAudio: L("Bleep", "Bip")
        case .audioToVideo: L("To Video", "Videoya")
        case .metadata: L("Metadata", "Meta Veri")
        case .readQR: L("Read QR", "QR Oku")
        case .recognizeText: L("Recognize Text", "Metni Tanı")
        case .unzip: L("Extract", "Aç")
        }
    }

    var windowTitle: String {
        switch self {
        case .adjustImage: L("Edit Photo", "Fotoğrafı Düzenle")
        case .cropImage: L("Crop & Rotate", "Kırp ve Döndür")
        case .rotateImage: L("Rotate & Mirror", "Döndür ve Aynala")
        case .imagesToPDF: L("Images to PDF", "Görsellerden PDF")
        case .compressPDF: L("Compress PDF", "PDF’yi Sıkıştır")
        case .muteVideo: L("Remove Audio", "Sesi Kaldır")
        case .unzip: L("Extract Archive", "Arşivi Aç")
        case .compressImage: L("Compress Images", "Görselleri Sıkıştır")
        case .annotateImage: L("Annotate", "İşaretle")
        case .redactImage: L("Redact Image", "Görseli Gizle")
        case .addBackground: L("Add Background", "Arka Plan Ekle")
        case .removeBackground: L("Remove Background", "Arka Planı Kaldır")
        case .resizeImage: L("Resize Image", "Görseli Boyutlandır")
        case .collage: L("Collage", "Kolaj")
        case .mergePDF: L("Merge PDFs", "PDF Birleştir")
        case .splitPDF: L("Split PDF", "PDF Böl")
        case .organizePDF: L("Organize Pages", "Sayfaları Düzenle")
        case .trimVideo: L("Trim Video", "Videoyu Kes")
        case .cropVideo: L("Crop Video", "Videoyu Kırp")
        case .compressVideo: L("Compress Video", "Videoyu Sıkıştır")
        case .videoSpeed: L("Change Speed", "Hızı Değiştir")
        case .videoFrames: L("Export Frames", "Kareleri Dışa Aktar")
        case .splitVideo: L("Split Video", "Videoyu Böl")
        case .redactVideo: L("Redact Video", "Videoyu Gizle")
        case .joinVideos: L("Join Videos", "Videoları Birleştir")
        case .trimAudio: L("Trim Audio", "Sesi Kes")
        case .normalizeAudio: L("Normalize Level", "Seviyeyi Dengele")
        case .audioChannels: L("Convert Audio Channels", "Ses Kanallarını Dönüştür")
        case .bleepAudio: L("Bleep Audio", "Sese Bip Ekle")
        case .audioToVideo: L("Audio to Video", "Sesten Videoya")
        case .metadata: L("Metadata", "Meta Veri")
        case .readQR: L("Read QR & Barcodes", "QR ve Barkod Oku")
        case .recognizeText: L("Recognize Text (OCR)", "Metni Tanı (OCR)")
        }
    }

    var subtitle: String {
        switch self {
        case .adjustImage: L("Light, color and detail", "Işık, renk ve detay")
        case .cropImage: L("Crop, rotate and flip", "Kırp, döndür, çevir")
        case .compressImage: L("Smaller files, same look", "Aynı görünüm, küçük dosya")
        case .annotateImage: L("Draw, arrows and text", "Çizim, ok ve metin")
        case .redactImage: L("Blur faces and text", "Yüz ve metni gizle")
        case .addBackground: L("Gradient frame and shadow", "Gradyan çerçeve ve gölge")
        case .removeBackground: L("Lift the subject", "Konuyu ayır")
        case .resizeImage: L("Exact pixel size", "Tam piksel boyutu")
        case .rotateImage: L("Turn and mirror", "Çevir ve aynala")
        case .collage: L("Grid of photos", "Fotoğraf ızgarası")
        case .imagesToPDF: L("Images into one PDF", "Görsellerden tek PDF")
        case .mergePDF: L("Combine documents", "Belgeleri birleştir")
        case .splitPDF: L("Pages or ranges", "Sayfa ya da aralık")
        case .organizePDF: L("Reorder, rotate, delete", "Sırala, döndür, sil")
        case .compressPDF: L("Optimize images inside", "İçteki görselleri optimize et")
        case .trimVideo: L("Keep the best part", "En iyi kısmı tut")
        case .cropVideo: L("Reframe the picture", "Kadrajı değiştir")
        case .compressVideo: L("HEVC presets", "HEVC ön ayarları")
        case .videoSpeed: L("Slow motion or timelapse", "Ağır çekim ya da hızlı")
        case .muteVideo: L("Remove the audio", "Sesi kaldır")
        case .videoFrames: L("Stills from video", "Videodan kareler")
        case .splitVideo: L("Cut into parts", "Parçalara ayır")
        case .redactVideo: L("Hide regions", "Bölgeleri gizle")
        case .joinVideos: L("One clip from many", "Birçok klipten tek video")
        case .trimAudio: L("In and out points", "Giriş ve çıkış noktaları")
        case .normalizeAudio: L("Peak or loudness", "Tepe ya da yükseklik")
        case .audioChannels: L("Mono, stereo and balance", "Mono, stereo, denge")
        case .bleepAudio: L("Censor words", "Kelimeleri sansürle")
        case .audioToVideo: L("Animated visualizer", "Animasyonlu görselleştirici")
        case .metadata: L("Inspect and remove", "İncele ve temizle")
        case .readQR: L("QR and barcodes", "QR ve barkodlar")
        case .recognizeText: L("Apple or local models", "Apple veya yerel modeller")
        case .unzip: L("Unpack safely", "Güvenle aç")
        }
    }

    var symbol: String {
        switch self {
        case .adjustImage: "slider.horizontal.3"
        case .cropImage: "crop"
        case .compressImage, .compressPDF, .compressVideo: "arrow.down.right.and.arrow.up.left"
        case .annotateImage: "pencil.tip.crop.circle"
        case .redactImage, .redactVideo: "eye.slash"
        case .addBackground: "rectangle.inset.filled"
        case .removeBackground: "person.and.background.dotted"
        case .resizeImage: "arrow.up.left.and.down.right.magnifyingglass"
        case .rotateImage: "rotate.right"
        case .collage: "square.grid.2x2"
        case .imagesToPDF: "doc.badge.plus"
        case .mergePDF: "doc.on.doc"
        case .splitPDF: "scissors"
        case .organizePDF: "square.grid.3x2"
        case .trimVideo, .trimAudio: "timeline.selection"
        case .cropVideo: "crop"
        case .videoSpeed: "gauge.with.dots.needle.67percent"
        case .muteVideo: "speaker.slash"
        case .videoFrames: "photo.on.rectangle.angled"
        case .splitVideo: "scissors"
        case .joinVideos: "rectangle.stack.badge.plus"
        case .normalizeAudio: "dial.medium"
        case .audioChannels: "hifispeaker.2"
        case .bleepAudio: "waveform.badge.exclamationmark"
        case .audioToVideo: "music.note.tv"
        case .metadata: "info.circle"
        case .readQR: "qrcode.viewfinder"
        case .recognizeText: "text.viewfinder"
        case .unzip: "archivebox"
        }
    }
}

extension ActionID {
    var title: String {
        switch self {
        case .float: L("Shelf", "Rafa Al")
        case .copy: L("Copy", "Kopyala")
        case .move: L("Move", "Taşı")
        case .copyPath: L("Copy Path", "Yolu Kopyala")
        case .duplicate: L("Duplicate", "Çoğalt")
        case .reveal: L("Reveal", "Göster")
        case .airDrop: "AirDrop"
        case .zip: L("Zip", "Sıkıştır")
        case .openTerminal: L("Terminal", "Terminal")
        }
    }

    var symbol: String {
        switch self {
        case .float: "tray.and.arrow.down"
        case .copy: "doc.on.clipboard"
        case .move: "folder"
        case .copyPath: "link"
        case .duplicate: "plus.square.on.square"
        case .reveal: "magnifyingglass"
        case .airDrop: "airplayaudio"
        case .zip: "doc.zipper"
        case .openTerminal: "apple.terminal"
        }
    }
}

extension WheelMode {
    var title: String {
        switch self {
        case .convert: L("Convert", "Dönüştür")
        case .tools: L("Tools", "Araçlar")
        case .actions: L("Actions", "Eylemler")
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .tools: "wrench.and.screwdriver"
        case .actions: "bolt"
        }
    }

    var key: String {
        switch self {
        case .convert: "⇧"
        case .tools: "⌘"
        case .actions: "⌃"
        }
    }

    /// Opens the same wheel for the current selection inside the window.
    var menuKey: KeyEquivalent {
        switch self {
        case .convert: "e"
        case .tools: "t"
        case .actions: "j"
        }
    }

    var menuKeyText: String { "⌘" + String(menuKey.character).uppercased() }

    var explanation: String {
        switch self {
        case .convert: L("Formats appear around your file. Drop it on one to get a converted copy.", "Biçimler dosyanın çevresinde belirir. Birine bırakın, dönüştürülmüş kopya oluşsun.")
        case .tools: L("Edit, compress, trim or redact in a focused editor.", "Düzenleyin, sıkıştırın, kesin ya da gizleyin; odaklı bir editörde.")
        case .actions: L("Shelf, copy, move, AirDrop, zip or open in Terminal.", "Raf, kopyala, taşı, AirDrop, sıkıştır ya da Terminal’de aç.")
        }
    }

    /// Slice icons used by the animated guide.
    var sampleSymbols: [String] {
        switch self {
        case .convert: ["photo", "photo", "photo", "doc.richtext", "photo.stack", "photo", "photo", "text.alignleft"]
        case .tools: ["slider.horizontal.3", "crop", "arrow.down.right.and.arrow.up.left", "pencil.tip.crop.circle", "eye.slash", "rectangle.inset.filled", "info.circle", "ellipsis"]
        case .actions: ["tray.and.arrow.down", "doc.on.clipboard", "folder", "link", "plus.square.on.square", "magnifyingglass", "airplayaudio", "doc.zipper"]
        }
    }
}

extension Error {
    var orangeMessage: String {
        (self as? OrangeError)?.message ?? localizedDescription
    }
}
