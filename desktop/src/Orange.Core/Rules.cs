namespace Orange;

public static class PageSelection
{
    public static IReadOnlyList<(int Start, int End)> Parse(string raw, int pageCount)
    {
        if (pageCount <= 0) throw new OrangeException(OrangeErrorCode.InvalidPages);
        var text = raw.Trim().ToLowerInvariant();
        if (text.Length == 0 || text is "all" or "hepsi" or "tümü") return [(1, pageCount)];
        var pieces = text.Split(',', ';').Select(piece => piece.Trim()).Where(piece => piece.Length > 0).ToArray();
        if (pieces.Length == 0) throw new OrangeException(OrangeErrorCode.InvalidPages);
        var ranges = new List<(int, int)>();
        foreach (var piece in pieces)
        {
            var ends = piece.Split('-').Select(part => part.Trim()).ToArray();
            int lower;
            int upper;
            switch (ends.Length)
            {
                case 1:
                    if (!int.TryParse(ends[0], out lower)) throw new OrangeException(OrangeErrorCode.InvalidPages);
                    upper = lower;
                    break;
                case 2:
                    if (!int.TryParse(ends[0], out lower)) throw new OrangeException(OrangeErrorCode.InvalidPages);
                    if (ends[1].Length == 0) upper = pageCount;
                    else if (!int.TryParse(ends[1], out upper)) throw new OrangeException(OrangeErrorCode.InvalidPages);
                    break;
                default:
                    throw new OrangeException(OrangeErrorCode.InvalidPages);
            }
            if (lower < 1 || upper > pageCount || lower > upper) throw new OrangeException(OrangeErrorCode.InvalidPages);
            ranges.Add((lower, upper));
        }
        return ranges;
    }
}

public sealed class DownloadProgressReader
{
    string pending = "";
    double partFloor;
    double previous;
    public List<string> Paths { get; } = [];

    public IReadOnlyList<double> Feed(string chunk)
    {
        pending += StripControls(chunk);
        var updates = new List<double>();
        while (true)
        {
            var breakIndex = pending.IndexOfAny(['\n', '\r']);
            if (breakIndex < 0) break;
            var line = pending[..breakIndex];
            pending = pending[(breakIndex + 1)..];
            var value = Interpret(line);
            if (value is { } number) updates.Add(Scale(number));
        }
        return updates;
    }

    public (double? Progress, IReadOnlyList<string> Paths) Finish()
    {
        var rest = pending;
        pending = "";
        var value = Interpret(rest);
        return (value is { } number ? Scale(number) : null, Paths);
    }

    double? Interpret(string line)
    {
        var trimmed = line.Trim();
        if (trimmed.Length == 0) return null;
        if (trimmed.StartsWith("ORANGEPROG:", StringComparison.Ordinal))
        {
            var raw = trimmed["ORANGEPROG:".Length..].Trim();
            if (!double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var value))
                return null;
            return Math.Clamp(value / 100, 0, 1);
        }
        if (trimmed.StartsWith("ORANGE:", StringComparison.Ordinal))
        {
            var path = trimmed["ORANGE:".Length..];
            if (path.Length > 0) Paths.Add(path);
            return null;
        }
        if (!trimmed.Contains("[download]", StringComparison.Ordinal)) return null;
        var match = System.Text.RegularExpressions.Regex.Match(trimmed, @"(\d+(?:\.\d+)?)%");
        if (!match.Success) return null;
        if (!double.TryParse(match.Groups[1].Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var percent))
            return null;
        return Math.Clamp(percent / 100, 0, 1);
    }

    double Scale(double raw)
    {
        if (raw + 0.05 < previous) partFloor = Math.Min(0.85, Math.Max(partFloor, previous));
        previous = raw;
        return Math.Min(0.99, partFloor + (1 - partFloor) * raw);
    }

    static string StripControls(string text)
    {
        var output = new System.Text.StringBuilder();
        var skipping = false;
        foreach (var character in text)
        {
            if (character == '\u001B')
            {
                skipping = true;
                continue;
            }
            if (skipping)
            {
                if (char.IsLetter(character)) skipping = false;
                continue;
            }
            output.Append(character);
        }
        return output.ToString();
    }
}

public static class LinkDiscovery
{
    public static Uri Normalize(string raw)
    {
        var text = raw.Trim();
        if (!text.Contains("://", StringComparison.Ordinal)) text = "https://" + text;
        if (!Uri.TryCreate(text, UriKind.Absolute, out var url)) throw new OrangeException(OrangeErrorCode.BadLink);
        var scheme = url.Scheme.ToLowerInvariant();
        if (scheme is not ("https" or "http") || string.IsNullOrEmpty(url.Host))
            throw new OrangeException(OrangeErrorCode.BadLink);
        return url;
    }

    public static bool IsPage(string? mimeType)
    {
        if (string.IsNullOrEmpty(mimeType)) return false;
        var type = mimeType.ToLowerInvariant();
        return type.StartsWith("text/", StringComparison.Ordinal) || type.Contains("html") || type.Contains("xml") || type.Contains("json");
    }

    public static Uri? MediaLink(string html, Uri page)
    {
        string[] keys = ["og:video:secure_url", "og:video:url", "og:video", "twitter:player:stream", "og:image:secure_url", "og:image"];
        foreach (var key in keys)
        {
            var escaped = System.Text.RegularExpressions.Regex.Escape(key);
            string[] patterns =
            [
                $"<meta[^>]+(?:property|name)=[\"']{escaped}[\"'][^>]*content=[\"']([^\"']+)[\"']",
                $"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']{escaped}[\"']"
            ];
            foreach (var pattern in patterns)
            {
                var value = FirstMatch(pattern, html);
                var resolved = value is null ? null : Resolve(value, page);
                if (resolved is not null) return resolved;
            }
        }
        var source = FirstMatch("<(?:video|source)[^>]+src=[\"']([^\"']+)[\"']", html);
        return source is null ? null : Resolve(source, page);
    }

    static string? FirstMatch(string pattern, string text)
    {
        var match = System.Text.RegularExpressions.Regex.Match(text, pattern, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return match.Success ? System.Net.WebUtility.HtmlDecode(match.Groups[1].Value) : null;
    }

    static Uri? Resolve(string value, Uri page)
    {
        if (!Uri.TryCreate(page, value, out var url)) return null;
        return url;
    }
}

public static class VideoBitrate
{
    public static int Compact(double pixels, double fps, double sourceBitsPerSecond, bool hevc)
    {
        var frames = Math.Max(fps, 1);
        var clean = pixels * frames * (hevc ? 0.12 : 0.20);
        var source = Math.Max(sourceBitsPerSecond, 0);
        var target = source > clean * 1.25 ? clean : (source > 1_000 ? Math.Min(source * 0.80, clean) : clean);
        if (source > 1_000) return Math.Max((int)Math.Round(Math.Min(target, source * 0.92)), 1);
        return (int)Math.Round(Math.Max(target, 250_000));
    }
}

public enum WheelModifier
{
    Convert,
    Tools,
    Actions
}

public static class WheelKeys
{
    public static WheelMode? Mode(bool shift, bool control, bool alt)
    {
        if (shift) return WheelMode.Convert;
        if (control) return WheelMode.Tools;
        if (alt) return WheelMode.Actions;
        return null;
    }
}
