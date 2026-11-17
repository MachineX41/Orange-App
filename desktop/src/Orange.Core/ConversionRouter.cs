namespace Orange;

public interface IFormatConverter
{
    Task<IReadOnlyList<string>> ConvertImageAsync(string path, ConvertTarget target, double quality, Action<double>? progress, CancellationToken cancellation);
    Task<string> RecognizeImageTextAsync(string path, CancellationToken cancellation);
    Task<IReadOnlyList<string>> ConvertVideoAsync(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation);
    Task<IReadOnlyList<string>> ConvertAudioAsync(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation);
    Task<IReadOnlyList<string>> PdfToImagesAsync(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation);
    Task<string> PdfTextAsync(string path, CancellationToken cancellation);
    Task<IReadOnlyList<string>> PdfToDocumentAsync(string path, ConvertTarget target, CancellationToken cancellation);
    Task<IReadOnlyList<string>> PresentationToPdfAsync(string path, CancellationToken cancellation);
    Task<string> PresentationOutlineAsync(string path, CancellationToken cancellation);
    Task<IReadOnlyList<string>> ConvertDocumentAsync(string path, ConvertTarget target, CancellationToken cancellation);
}

public static class ConversionRouter
{
    public static async Task<IReadOnlyList<string>> ConvertAsync(
        string path,
        ConvertTarget target,
        IFormatConverter converter,
        double quality = 0.9,
        Action<double>? progress = null,
        CancellationToken cancellation = default)
    {
        switch (Catalog.Kind(path))
        {
            case MediaKind.Image:
                if (target == ConvertTarget.Txt)
                {
                    var text = await converter.RecognizeImageTextAsync(path, cancellation);
                    if (string.IsNullOrWhiteSpace(text)) throw new OrangeException(OrangeErrorCode.NothingFound);
                    return [UniqueDestination.WriteText(text, path)];
                }
                return await converter.ConvertImageAsync(path, target, quality, progress, cancellation);
            case MediaKind.Video:
                return await converter.ConvertVideoAsync(path, target, progress, cancellation);
            case MediaKind.Audio:
                return await converter.ConvertAudioAsync(path, target, progress, cancellation);
            case MediaKind.Pdf:
                return target switch
                {
                    ConvertTarget.Png or ConvertTarget.Jpeg or ConvertTarget.Heic or ConvertTarget.Tiff or ConvertTarget.Webp
                        => await converter.PdfToImagesAsync(path, target, progress, cancellation),
                    ConvertTarget.Txt => WriteRequired(await converter.PdfTextAsync(path, cancellation), path),
                    _ => await converter.PdfToDocumentAsync(path, target, cancellation)
                };
            case MediaKind.Document when Catalog.IsPresentation(path):
                return target switch
                {
                    ConvertTarget.Pdf => await converter.PresentationToPdfAsync(path, cancellation),
                    ConvertTarget.Txt => WriteRequired(await converter.PresentationOutlineAsync(path, cancellation), path),
                    _ => throw new OrangeException(OrangeErrorCode.Unsupported, target.FileExtension().ToUpperInvariant())
                };
            case MediaKind.Document:
                return await converter.ConvertDocumentAsync(path, target, cancellation);
            default:
                throw new OrangeException(OrangeErrorCode.Unsupported, Path.GetExtension(path).TrimStart('.').ToUpperInvariant());
        }
    }

    static IReadOnlyList<string> WriteRequired(string text, string beside)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new OrangeException(OrangeErrorCode.NothingFound);
        return [UniqueDestination.WriteText(text, beside)];
    }
}
