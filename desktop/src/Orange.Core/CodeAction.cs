namespace Orange;

public abstract record CodeAction
{
    public Uri? Url => this switch
    {
        WebAction web => web.Address,
        EmailAction email => email.Address,
        PhoneAction phone => phone.Address,
        MessageAction message => message.Address,
        MapAction map => map.Address,
        _ => null
    };

    public bool IsInsecure => this is WebAction web && string.Equals(web.Address.Scheme, "http", StringComparison.OrdinalIgnoreCase);

    public string? Destination => this switch
    {
        WebAction web => StripWww(web.Address.Host),
        EmailAction email => Bare(email.Address),
        PhoneAction phone => Bare(phone.Address),
        MessageAction message => Bare(message.Address),
        WifiAction wifi => wifi.Ssid,
        _ => null
    };

    public sealed record WebAction(Uri Address) : CodeAction;
    public sealed record EmailAction(Uri Address) : CodeAction;
    public sealed record PhoneAction(Uri Address) : CodeAction;
    public sealed record MessageAction(Uri Address) : CodeAction;
    public sealed record MapAction(Uri Address) : CodeAction;
    public sealed record WifiAction(string Ssid, string? Password) : CodeAction;
    public sealed record TextAction : CodeAction
    {
        public static readonly TextAction Instance = new();
    }

    public static CodeAction Parse(string payload)
    {
        var text = payload.Trim();
        if (string.IsNullOrEmpty(text)) return TextAction.Instance;
        if (text.Any(character => character is '\n' or '\r') && !text.StartsWith("WIFI:", StringComparison.OrdinalIgnoreCase))
            return TextAction.Instance;
        var lower = text.ToLowerInvariant();
        if (lower.StartsWith("wifi:", StringComparison.Ordinal)) return Wifi(text);
        if (lower.StartsWith("matmsg:", StringComparison.Ordinal)) return Matmsg(text);
        if (lower.StartsWith("smsto:", StringComparison.Ordinal))
        {
            var body = text[6..];
            var split = body.Split(':', 2);
            var builder = new UriBuilder { Scheme = "sms", Path = split[0] };
            if (split.Length > 1) builder.Query = "body=" + Uri.EscapeDataString(split[1]);
            return new MessageAction(builder.Uri);
        }

        if (Uri.TryCreate(text, UriKind.Absolute, out var url) && url.Scheme is { } scheme)
        {
            switch (scheme.ToLowerInvariant())
            {
                case "http":
                case "https":
                    return url.Host.Contains('.') ? new WebAction(url) : TextAction.Instance;
                case "mailto":
                    return new EmailAction(url);
                case "tel":
                    return new PhoneAction(url);
                case "sms":
                case "imessage":
                    return new MessageAction(url);
                case "geo":
                    var map = MapUrl(text[4..]);
                    return map is null ? TextAction.Instance : new MapAction(map);
                default:
                    if (!lower.StartsWith("www.", StringComparison.Ordinal)) return TextAction.Instance;
                    break;
            }
        }

        if (LooksLikeHost(lower) && Uri.TryCreate("https://" + text, UriKind.Absolute, out var web) && web.Host.Contains('.'))
            return new WebAction(web);
        if (LooksLikeEmail(text) && Uri.TryCreate("mailto:" + text, UriKind.Absolute, out var mail))
            return new EmailAction(mail);
        return TextAction.Instance;
    }

    static string? StripWww(string host) =>
        host.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? host[4..] : host;

    static string? Bare(Uri url)
    {
        var absolute = url.AbsoluteUri;
        var colon = absolute.IndexOf(':');
        var rest = colon >= 0 ? absolute[(colon + 1)..] : absolute;
        var query = rest.Split('?')[0];
        return Uri.UnescapeDataString(query);
    }

    static bool LooksLikeHost(string text)
    {
        if (text.Contains(' ') || text.Contains('@')) return false;
        var host = text.Split('/', '?', '#', ':').FirstOrDefault() ?? "";
        var labels = host.Split('.');
        if (labels.Length < 2) return false;
        var tld = labels[^1];
        if (tld.Length < 2 || !tld.All(char.IsLetter)) return false;
        return host.All(character => char.IsLetterOrDigit(character) || character is '.' or '-');
    }

    static bool LooksLikeEmail(string text)
    {
        var parts = text.Split('@');
        return parts.Length == 2 && !text.Contains(' ') && LooksLikeHost(parts[1].ToLowerInvariant());
    }

    static Dictionary<string, string> Fields(string body)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var key = "";
        var value = "";
        var readingValue = false;
        var escaped = false;
        foreach (var character in body)
        {
            if (escaped)
            {
                value += character;
                escaped = false;
            }
            else if (character == '\\' && readingValue)
            {
                escaped = true;
            }
            else if (character == ':' && !readingValue)
            {
                readingValue = true;
            }
            else if (character == ';')
            {
                if (key.Length > 0) result[key.ToUpperInvariant()] = value;
                key = "";
                value = "";
                readingValue = false;
            }
            else if (readingValue)
            {
                value += character;
            }
            else
            {
                key += character;
            }
        }
        if (key.Length > 0) result[key.ToUpperInvariant()] = value;
        return result;
    }

    static CodeAction Wifi(string text)
    {
        var values = Fields(text[5..]);
        if (!values.TryGetValue("S", out var ssid) || ssid.Length == 0) return TextAction.Instance;
        values.TryGetValue("P", out var password);
        if (string.IsNullOrEmpty(password)) password = null;
        if (string.Equals(values.GetValueOrDefault("T"), "nopass", StringComparison.OrdinalIgnoreCase)) password = null;
        return new WifiAction(ssid, password);
    }

    static CodeAction Matmsg(string text)
    {
        var values = Fields(text[7..]);
        if (!values.TryGetValue("TO", out var address) || !LooksLikeEmail(address)) return TextAction.Instance;
        var query = new List<string>();
        if (values.TryGetValue("SUB", out var subject)) query.Add("subject=" + Uri.EscapeDataString(subject));
        if (values.TryGetValue("BODY", out var body)) query.Add("body=" + Uri.EscapeDataString(body));
        var uri = new Uri("mailto:" + address + (query.Count > 0 ? "?" + string.Join("&", query) : ""));
        return new EmailAction(uri);
    }

    static Uri? MapUrl(string geo)
    {
        var head = geo.Split('?').FirstOrDefault() ?? "";
        var coordinates = head.Split(',').Take(2).Select(piece => double.TryParse(piece, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var value) ? value : double.NaN).ToArray();
        if (coordinates.Length != 2 || coordinates.Any(double.IsNaN)) return null;
        if (Math.Abs(coordinates[0]) > 90 || Math.Abs(coordinates[1]) > 180) return null;
        var culture = System.Globalization.CultureInfo.InvariantCulture;
        return new Uri($"https://maps.apple.com/?ll={coordinates[0].ToString(culture)},{coordinates[1].ToString(culture)}&q={coordinates[0].ToString(culture)},{coordinates[1].ToString(culture)}");
    }
}
