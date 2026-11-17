namespace Orange;

public enum MediaKind
{
    Image,
    Video,
    Audio,
    Pdf,
    Document,
    Archive,
    Other
}

public enum ConvertTarget
{
    Jpeg, Png, Heic, Webp, Avif, Tiff, Bmp, Gif,
    Pdf, Txt, Docx, Rtf, Html, Odt,
    Mp4, Mov, M4v,
    M4a, Wav, Aiff
}

public static class ConvertTargets
{
    public static string FileExtension(this ConvertTarget target) => target switch
    {
        ConvertTarget.Jpeg => "jpg",
        _ => target.ToString().ToLowerInvariant()
    };

    public static bool IsLossyImage(this ConvertTarget target) =>
        target is ConvertTarget.Jpeg or ConvertTarget.Heic or ConvertTarget.Webp or ConvertTarget.Avif;

    public static bool IsImage(this ConvertTarget target) => target is
        ConvertTarget.Jpeg or ConvertTarget.Png or ConvertTarget.Heic or ConvertTarget.Webp
        or ConvertTarget.Avif or ConvertTarget.Tiff or ConvertTarget.Bmp or ConvertTarget.Gif;
}

/// <summary>
/// ImageMagick on Windows and Linux can write every image target Orange offers.
/// </summary>
public static class ImageCapabilities
{
    public static bool CanWrite(ConvertTarget target) => target.IsImage();
}

public enum ToolId
{
    AdjustImage, CropImage, CompressImage, AnnotateImage, RedactImage, AddBackground,
    RemoveBackground, ResizeImage, RotateImage, Collage, ImagesToPdf,
    MergePdf, SplitPdf, OrganizePdf, CompressPdf,
    TrimVideo, CropVideo, CompressVideo, VideoSpeed, MuteVideo, VideoFrames, SplitVideo, RedactVideo, JoinVideos,
    TrimAudio, NormalizeAudio, AudioChannels, BleepAudio, AudioToVideo,
    Metadata, ReadQr, Unzip
}

public static class ToolIds
{
    public static IReadOnlySet<MediaKind> Kinds(this ToolId tool) => tool switch
    {
        ToolId.AdjustImage or ToolId.CropImage or ToolId.CompressImage or ToolId.AnnotateImage
            or ToolId.RedactImage or ToolId.AddBackground or ToolId.RemoveBackground
            or ToolId.ResizeImage or ToolId.RotateImage or ToolId.Collage or ToolId.ImagesToPdf => One(MediaKind.Image),
        ToolId.MergePdf or ToolId.SplitPdf or ToolId.OrganizePdf or ToolId.CompressPdf => One(MediaKind.Pdf),
        ToolId.TrimVideo or ToolId.CropVideo or ToolId.CompressVideo or ToolId.VideoSpeed
            or ToolId.MuteVideo or ToolId.VideoFrames or ToolId.SplitVideo or ToolId.RedactVideo
            or ToolId.JoinVideos => One(MediaKind.Video),
        ToolId.TrimAudio or ToolId.NormalizeAudio or ToolId.AudioChannels or ToolId.BleepAudio
            or ToolId.AudioToVideo => One(MediaKind.Audio),
        ToolId.Metadata => Set(MediaKind.Image, MediaKind.Video, MediaKind.Audio, MediaKind.Pdf),
        ToolId.ReadQr => Set(MediaKind.Image, MediaKind.Pdf),
        ToolId.Unzip => One(MediaKind.Archive),
        _ => One(MediaKind.Other)
    };

    public static int MinimumFiles(this ToolId tool) => tool switch
    {
        ToolId.MergePdf or ToolId.JoinVideos or ToolId.Collage => 2,
        _ => 1
    };

    public static bool AcceptsMany(this ToolId tool) => tool switch
    {
        ToolId.CompressImage or ToolId.RemoveBackground or ToolId.ReadQr or ToolId.CompressPdf
            or ToolId.MuteVideo or ToolId.CompressVideo or ToolId.NormalizeAudio or ToolId.ImagesToPdf
            or ToolId.Collage or ToolId.MergePdf or ToolId.JoinVideos or ToolId.Unzip => true,
        _ => false
    };

    public static MediaKind PrimaryKind(this ToolId tool) => tool switch
    {
        ToolId.Metadata or ToolId.ReadQr => MediaKind.Image,
        _ => tool.Kinds().FirstOrDefault()
    };

    static HashSet<MediaKind> One(MediaKind kind) => [kind];
    static HashSet<MediaKind> Set(params MediaKind[] kinds) => [.. kinds];
}

public static class Catalog
{
    static readonly HashSet<string> PresentationExtensions = ["pptx", "pptm", "ppsx", "ppsm", "potx", "potm"];
    static readonly HashSet<string> DocumentExtensions =
    [
        "txt", "text", "md", "markdown", "rtf", "doc", "docx", "odt", "html", "htm", "webarchive",
        .. PresentationExtensions
    ];
    static readonly HashSet<string> ArchiveExtensions =
        ["zip", "tar", "tgz", "gz", "bz2", "tbz", "tbz2", "xz", "txz", "7z", "rar"];
    static readonly HashSet<string> ImageExtensions =
        ["jpg", "jpeg", "jpe", "png", "heic", "heif", "webp", "avif", "tif", "tiff", "bmp", "gif"];
    static readonly HashSet<string> VideoExtensions = ["mp4", "mov", "m4v", "mkv", "webm", "avi"];
    static readonly HashSet<string> AudioExtensions = ["mp3", "m4a", "wav", "aiff", "aif", "aac", "flac", "caf", "ogg"];

    public static bool IsPresentation(string path) =>
        PresentationExtensions.Contains(CanonicalExtension(Path.GetExtension(path)));

    public static string CanonicalExtension(string extension)
    {
        var ext = extension.Trim().TrimStart('.').ToLowerInvariant();
        return ext switch
        {
            "jpeg" or "jpe" => "jpg",
            "tif" => "tiff",
            "heif" => "heic",
            "htm" => "html",
            "markdown" => "md",
            "aif" => "aiff",
            _ => ext
        };
    }

    public static MediaKind Kind(string path)
    {
        var ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        if (DocumentExtensions.Contains(ext)) return MediaKind.Document;
        if (ArchiveExtensions.Contains(ext)) return MediaKind.Archive;
        if (ext == "pdf") return MediaKind.Pdf;
        if (ext == "svg") return MediaKind.Other;
        if (ImageExtensions.Contains(ext)) return MediaKind.Image;
        if (VideoExtensions.Contains(ext)) return MediaKind.Video;
        if (AudioExtensions.Contains(ext)) return MediaKind.Audio;
        return MediaKind.Other;
    }

    public static IReadOnlyList<ConvertTarget> ConvertTargetsFor(string path)
    {
        var own = CanonicalExtension(Path.GetExtension(path));
        IEnumerable<ConvertTarget> list = Kind(path) switch
        {
            MediaKind.Image => ImageCapabilitiesFilter().Append(ConvertTarget.Pdf).Append(ConvertTarget.Txt),
            MediaKind.Video => [ConvertTarget.Mp4, ConvertTarget.Mov, ConvertTarget.M4v, ConvertTarget.Gif, ConvertTarget.M4a],
            MediaKind.Audio => [ConvertTarget.M4a, ConvertTarget.Wav, ConvertTarget.Aiff],
            MediaKind.Pdf => [ConvertTarget.Png, ConvertTarget.Jpeg, ConvertTarget.Webp, ConvertTarget.Txt, ConvertTarget.Docx, ConvertTarget.Rtf],
            MediaKind.Document => IsPresentation(path)
                ? [ConvertTarget.Pdf, ConvertTarget.Txt]
                : [ConvertTarget.Pdf, ConvertTarget.Docx, ConvertTarget.Rtf, ConvertTarget.Html, ConvertTarget.Odt, ConvertTarget.Txt],
            _ => []
        };
        return list.Where(target => target.FileExtension() != own).ToArray();
    }

    public static IReadOnlyList<ConvertTarget> CommonConvertTargets(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) return [];
        var kind = Kind(paths[0]);
        if (paths.Any(path => Kind(path) != kind)) return [];
        var shared = ConvertTargetsFor(paths[0]).ToList();
        foreach (var path in paths.Skip(1))
        {
            var allowed = ConvertTargetsFor(path).ToHashSet();
            shared.RemoveAll(target => !allowed.Contains(target));
        }
        return shared;
    }

    public static IReadOnlyList<ToolId> Tools(MediaKind kind) => kind switch
    {
        MediaKind.Image =>
        [
            ToolId.AdjustImage, ToolId.CropImage, ToolId.CompressImage, ToolId.AnnotateImage, ToolId.RedactImage,
            ToolId.AddBackground, ToolId.RemoveBackground, ToolId.Metadata, ToolId.ResizeImage, ToolId.RotateImage,
            ToolId.ReadQr, ToolId.Collage, ToolId.ImagesToPdf
        ],
        MediaKind.Video =>
        [
            ToolId.TrimVideo, ToolId.CropVideo, ToolId.CompressVideo, ToolId.VideoSpeed, ToolId.MuteVideo,
            ToolId.VideoFrames, ToolId.SplitVideo, ToolId.RedactVideo, ToolId.Metadata, ToolId.JoinVideos
        ],
        MediaKind.Audio =>
        [
            ToolId.TrimAudio, ToolId.NormalizeAudio, ToolId.AudioChannels, ToolId.BleepAudio, ToolId.AudioToVideo, ToolId.Metadata
        ],
        MediaKind.Pdf =>
        [
            ToolId.MergePdf, ToolId.SplitPdf, ToolId.OrganizePdf, ToolId.CompressPdf, ToolId.ReadQr, ToolId.Metadata
        ],
        MediaKind.Archive => [ToolId.Unzip],
        _ => []
    };

    public static IReadOnlyList<ToolId> CommonTools(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) return [];
        var kinds = paths.Select(Kind).ToArray();
        return Tools(kinds[0]).Where(tool =>
            kinds.All(kind => tool.Kinds().Contains(kind))
            && (paths.Count == 1 ? tool.MinimumFiles() <= 1 : tool.AcceptsMany())).ToArray();
    }

    static IEnumerable<ConvertTarget> ImageCapabilitiesFilter() =>
        new[]
        {
            ConvertTarget.Jpeg, ConvertTarget.Png, ConvertTarget.Heic, ConvertTarget.Webp,
            ConvertTarget.Avif, ConvertTarget.Tiff, ConvertTarget.Bmp, ConvertTarget.Gif
        }.Where(ImageCapabilities.CanWrite);
}
