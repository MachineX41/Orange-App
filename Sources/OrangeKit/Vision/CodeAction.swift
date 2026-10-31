import Foundation

/// What a scanned QR or barcode payload points to. Only well-known, harmless schemes become openable.
public enum CodeAction: Hashable, Sendable {
    case web(URL)
    case email(URL)
    case phone(URL)
    case message(URL)
    case map(URL)
    case wifi(ssid: String, password: String?)
    case text

    public var url: URL? {
        switch self {
        case .web(let url), .email(let url), .phone(let url), .message(let url), .map(let url): url
        case .wifi, .text: nil
        }
    }

    /// Plain `http` links can be tampered with on the way, so they are flagged before opening.
    public var isInsecure: Bool {
        if case .web(let url) = self { return url.scheme?.lowercased() == "http" }
        return false
    }

    /// The part a person should check before opening, e.g. `example.com` or the phone number.
    public var destination: String? {
        switch self {
        case .web(let url): url.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        case .email(let url), .phone(let url), .message(let url): url.absoluteString.split(separator: ":", maxSplits: 1).last.map { String($0).components(separatedBy: "?")[0] }.flatMap { $0.removingPercentEncoding }
        case .map: nil
        case .wifi(let ssid, _): ssid
        case .text: nil
        }
    }

    public static func parse(_ payload: String) -> CodeAction {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isNewline }) || text.uppercased().hasPrefix("WIFI:") else {
            return .text
        }
        let lower = text.lowercased()

        if lower.hasPrefix("wifi:") { return wifi(text) }
        if lower.hasPrefix("matmsg:") { return matmsg(text) }
        if lower.hasPrefix("smsto:") {
            let parts = text.dropFirst(6).split(separator: ":", maxSplits: 1).map(String.init)
            var components = URLComponents()
            components.scheme = "sms"
            components.path = parts.first ?? ""
            if parts.count > 1 { components.queryItems = [URLQueryItem(name: "body", value: parts[1])] }
            return components.url.map(CodeAction.message) ?? .text
        }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return url.host()?.contains(".") == true ? .web(url) : .text
            case "mailto":
                return .email(url)
            case "tel":
                return .phone(url)
            case "sms", "imessage":
                return .message(url)
            case "geo":
                return mapURL(geo: String(text.dropFirst(4))).map(CodeAction.map) ?? .text
            default:
                if !lower.hasPrefix("www.") { return .text }
            }
        }

        if looksLikeHost(lower), let url = URL(string: "https://" + text), url.host()?.contains(".") == true {
            return .web(url)
        }
        if looksLikeEmail(text), let url = URL(string: "mailto:" + text) {
            return .email(url)
        }
        return .text
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        guard !text.contains(" "), !text.contains("@") else { return false }
        let host = text.split(whereSeparator: { "/?#:".contains($0) }).first.map(String.init) ?? ""
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return false }
        return host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@")
        return parts.count == 2 && !text.contains(" ") && looksLikeHost(String(parts[1]).lowercased())
    }

    private static func fields(_ body: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var readingValue = false
        var escaped = false
        for character in body {
            if escaped {
                value.append(character)
                escaped = false
            } else if character == "\\" && readingValue {
                escaped = true
            } else if character == ":" && !readingValue {
                readingValue = true
            } else if character == ";" {
                if !key.isEmpty { result[key.uppercased()] = value }
                key = ""
                value = ""
                readingValue = false
            } else if readingValue {
                value.append(character)
            } else {
                key.append(character)
            }
        }
        if !key.isEmpty { result[key.uppercased()] = value }
        return result
    }

    private static func wifi(_ text: String) -> CodeAction {
        let values = fields(text.dropFirst(5))
        guard let ssid = values["S"], !ssid.isEmpty else { return .text }
        let password = values["P"].flatMap { $0.isEmpty ? nil : $0 }
        return .wifi(ssid: ssid, password: values["T"]?.lowercased() == "nopass" ? nil : password)
    }

    private static func matmsg(_ text: String) -> CodeAction {
        let values = fields(text.dropFirst(7))
        guard let address = values["TO"], looksLikeEmail(address) else { return .text }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [("subject", values["SUB"]), ("body", values["BODY"])]
            .compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.url.map(CodeAction.email) ?? .text
    }

    private static func mapURL(geo: String) -> URL? {
        let coordinates = geo.split(separator: "?").first?.split(separator: ",").prefix(2).compactMap { Double($0) } ?? []
        guard coordinates.count == 2, abs(coordinates[0]) <= 90, abs(coordinates[1]) <= 180 else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(coordinates[0]),\(coordinates[1])&q=\(coordinates[0]),\(coordinates[1])")
    }
}
