namespace Orange;

public enum LanguageChoice
{
    System,
    Turkish,
    English
}

public static class Lang
{
    public static LanguageChoice Choice { get; set; } = LanguageChoice.System;
    public static Func<IReadOnlyList<string>>? PreferredLanguages { get; set; }

    public static bool IsTurkish => Choice switch
    {
        LanguageChoice.Turkish => true,
        LanguageChoice.English => false,
        _ => SystemPrefersTurkish(PreferredLanguages?.Invoke())
    };

    public static bool SystemPrefersTurkish(IReadOnlyList<string>? preferred = null)
    {
        preferred ??= PreferredLanguages?.Invoke() ?? CultureLanguages();
        foreach (var identifier in preferred)
        {
            switch (LanguageCode(identifier))
            {
                case "tr": return true;
                case "en": return false;
            }
        }
        return false;
    }

    public static string T(string english, string turkish) => IsTurkish ? turkish : english;

    static string LanguageCode(string identifier)
    {
        var cut = identifier.Split('-', '_').FirstOrDefault() ?? "";
        return cut.ToLowerInvariant();
    }

    static IReadOnlyList<string> CultureLanguages() => [System.Globalization.CultureInfo.CurrentUICulture.Name];
}

public enum OrangeErrorCode
{
    Unreadable,
    Unsupported,
    WriteFailed,
    InvalidPages,
    UnsafeArchive,
    Empty,
    Cancelled,
    NothingFound,
    NotSmaller,
    NoSubject,
    BadLink,
    NeedsDownloader,
    ToolFailed
}

public sealed class OrangeException : Exception
{
    public OrangeException(OrangeErrorCode code, string? name = null)
        : base(MessageFor(code, name))
    {
        Code = code;
        Name = name;
    }

    public OrangeErrorCode Code { get; }
    public string? Name { get; }

    public static string MessageFor(OrangeErrorCode code, string? name) => code switch
    {
        OrangeErrorCode.Unreadable => Lang.T($"Couldn't read {name}.", $"{name} okunamadı."),
        OrangeErrorCode.Unsupported => Lang.T($"{name} can't be used for this.", $"{name} bu işlem için uygun değil."),
        OrangeErrorCode.WriteFailed => Lang.T($"Couldn't write {name}.", $"{name} yazılamadı."),
        OrangeErrorCode.InvalidPages => Lang.T("That page range isn't valid.", "Sayfa aralığı geçersiz."),
        OrangeErrorCode.UnsafeArchive => Lang.T("The archive contains an unsafe path.", "Arşiv güvenli olmayan bir yol içeriyor."),
        OrangeErrorCode.Empty => Lang.T("Choose a file first.", "Önce bir dosya seçin."),
        OrangeErrorCode.Cancelled => Lang.T("Cancelled.", "İptal edildi."),
        OrangeErrorCode.NothingFound => Lang.T("Nothing was found.", "Hiçbir şey bulunamadı."),
        OrangeErrorCode.NotSmaller => Lang.T("This file is already as small as it gets.", "Bu dosya zaten olabildiğince küçük."),
        OrangeErrorCode.NoSubject => Lang.T("No clear subject was found in this image.", "Bu görselde belirgin bir nesne bulunamadı."),
        OrangeErrorCode.BadLink => Lang.T("That link isn't a reachable web address.", "Bu link erişilebilir bir web adresi değil."),
        OrangeErrorCode.NeedsDownloader => Lang.T(
            "This site needs yt-dlp. Install it, then try again.",
            "Bu site için yt-dlp gerekiyor. Kurup tekrar deneyin."),
        OrangeErrorCode.ToolFailed => name ?? Lang.T("The tool failed.", "Araç başarısız oldu."),
        _ => name ?? ""
    };
}
