import Foundation

public enum OrangeError: Error, Equatable, Sendable, LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case writeFailed(String)
    case invalidPages
    case unsafeArchive
    case empty
    case cancelled

    public var errorDescription: String? {
        let turkish = Locale.preferredLanguages.first?.hasPrefix("tr") == true
        switch self {
        case .unreadable(let name):
            return turkish ? "\(name) okunamadı." : "Couldn’t read \(name)."
        case .unsupported(let name):
            return turkish ? "\(name) bu işlem için uygun değil." : "\(name) can’t be used for this."
        case .writeFailed(let name):
            return turkish ? "\(name) yazılamadı." : "Couldn’t write \(name)."
        case .invalidPages:
            return turkish ? "Sayfa aralığı geçersiz." : "That page range isn’t valid."
        case .unsafeArchive:
            return turkish ? "Arşiv güvenli olmayan bir yol içeriyor." : "The archive contains an unsafe path."
        case .empty:
            return turkish ? "Önce bir dosya seçin." : "Choose a file first."
        case .cancelled:
            return turkish ? "İptal edildi." : "Cancelled."
        }
    }
}
