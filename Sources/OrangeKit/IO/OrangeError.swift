import Foundation

public enum OrangeError: Error, Equatable, Sendable, LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case writeFailed(String)
    case invalidPages
    case unsafeArchive
    case empty
    case cancelled
    case nothingFound
    case notSmaller
    case noSubject
    case badLink
    case needsDownloader
    case toolFailed(String)

    public var message: String {
        switch self {
        case .unreadable(let name):
            Lang.t("Couldn’t read \(name).", "\(name) okunamadı.")
        case .unsupported(let name):
            Lang.t("\(name) can’t be used for this.", "\(name) bu işlem için uygun değil.")
        case .writeFailed(let name):
            Lang.t("Couldn’t write \(name).", "\(name) yazılamadı.")
        case .invalidPages:
            Lang.t("That page range isn’t valid.", "Sayfa aralığı geçersiz.")
        case .unsafeArchive:
            Lang.t("The archive contains an unsafe path.", "Arşiv güvenli olmayan bir yol içeriyor.")
        case .empty:
            Lang.t("Choose a file first.", "Önce bir dosya seçin.")
        case .cancelled:
            Lang.t("Cancelled.", "İptal edildi.")
        case .nothingFound:
            Lang.t("Nothing was found.", "Hiçbir şey bulunamadı.")
        case .notSmaller:
            Lang.t("This file is already as small as it gets.", "Bu dosya zaten olabildiğince küçük.")
        case .noSubject:
            Lang.t("No clear subject was found in this image.", "Bu görselde belirgin bir nesne bulunamadı.")
        case .badLink:
            Lang.t("That link isn’t a reachable web address.", "Bu link erişilebilir bir web adresi değil.")
        case .needsDownloader:
            Lang.t(
                "This site needs yt-dlp. Install it with “brew install yt-dlp”, then try again.",
                "Bu site için yt-dlp gerekiyor. “brew install yt-dlp” ile kurup tekrar deneyin."
            )
        case .toolFailed(let text):
            text
        }
    }

    public var errorDescription: String? { message }
}
