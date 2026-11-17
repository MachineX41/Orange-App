namespace Orange;

public sealed class Engine : IFormatConverter
{
    public static readonly Engine Shared = new();

    public Task<IReadOnlyList<string>> ConvertImageAsync(string path, ConvertTarget target, double quality, Action<double>? progress, CancellationToken cancellation) =>
        ImageStudio.Convert(path, target, quality, cancellation);

    public async Task<string> RecognizeImageTextAsync(string path, CancellationToken cancellation) =>
        await VisionStudio.RecognizeAsync(path, cancellation);

    public Task<IReadOnlyList<string>> ConvertVideoAsync(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation) =>
        MediaStudio.Convert(path, target, progress, cancellation);

    public Task<IReadOnlyList<string>> ConvertAudioAsync(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation) =>
        MediaStudio.Convert(path, target, progress, cancellation);

    public Task<IReadOnlyList<string>> PdfToImagesAsync(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation) =>
        PdfStudio.ToImages(path, target, progress, cancellation);

    public Task<string> PdfTextAsync(string path, CancellationToken cancellation) =>
        Task.FromResult(PdfStudio.Text(path));

    public Task<IReadOnlyList<string>> PdfToDocumentAsync(string path, ConvertTarget target, CancellationToken cancellation) =>
        DocumentStudio.Convert(path, target, cancellation);

    public Task<IReadOnlyList<string>> PresentationToPdfAsync(string path, CancellationToken cancellation) =>
        PresentationConverter.Convert(path, cancellation);

    public Task<string> PresentationOutlineAsync(string path, CancellationToken cancellation) =>
        PresentationConverter.Outline(path, cancellation);

    public Task<IReadOnlyList<string>> ConvertDocumentAsync(string path, ConvertTarget target, CancellationToken cancellation) =>
        DocumentStudio.Convert(path, target, cancellation);
}
