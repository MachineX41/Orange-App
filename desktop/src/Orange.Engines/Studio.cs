namespace Orange;

public sealed class PhotoAdjustments
{
    public double Exposure { get; set; }
    public double Brightness { get; set; }
    public double Contrast { get; set; }
    public double Highlights { get; set; }
    public double Shadows { get; set; }
    public double Saturation { get; set; }
    public double Vibrance { get; set; }
    public double Warmth { get; set; }
    public double Tint { get; set; }
    public double Sharpness { get; set; }
    public double Vignette { get; set; }
    public bool IsIdentity => Exposure == 0 && Brightness == 0 && Contrast == 0 && Highlights == 0 && Shadows == 0
        && Saturation == 0 && Vibrance == 0 && Warmth == 0 && Tint == 0 && Sharpness == 0 && Vignette == 0;
}

public sealed class ToolRequest
{
    public double Quality { get; set; } = 0.85;
    public Rect Crop { get; set; } = new(0, 0, 1, 1);
    public int Width { get; set; }
    public int Height { get; set; }
    public int QuartersClockwise { get; set; }
    public bool FlipHorizontal { get; set; }
    public bool FlipVertical { get; set; }
    public PhotoAdjustments Adjust { get; set; } = new();
    public string Text { get; set; } = "";
    public string Color { get; set; } = "#F26B1D";
    public string RedactStyle { get; set; } = "pixelate";
    public List<Rect> Regions { get; set; } = [new(0.1, 0.1, 0.3, 0.2)];
    public string PageSelection { get; set; } = "all";
    public int ChunkSize { get; set; } = 1;
    public string SplitKind { get; set; } = "every";
    public double Start { get; set; }
    public double End { get; set; }
    public double Speed { get; set; } = 1;
    public bool ToMono { get; set; }
    public double NormalizeDb { get; set; } = -1;
    public bool BleepTone { get; set; }
    public string Background { get; set; } = "#FFFFFF";
    public string PageOrder { get; set; } = "";
    public int Columns { get; set; }
    public string VideoQuality { get; set; } = "balanced";
}

public static class OrangeStudio
{
    public static Task<IReadOnlyList<string>> ConvertAsync(string path, ConvertTarget target, double quality = 0.9, Action<double>? progress = null, CancellationToken cancellation = default) =>
        ConversionRouter.ConvertAsync(path, target, Engine.Shared, quality, progress, cancellation);

    public static Task<IReadOnlyList<string>> RunAsync(ToolId tool, IReadOnlyList<string> paths, ToolRequest? request = null, Action<double>? progress = null, CancellationToken cancellation = default)
    {
        if (paths.Count == 0) throw new OrangeException(OrangeErrorCode.Empty);
        if (paths.Count < tool.MinimumFiles()) throw new OrangeException(OrangeErrorCode.Empty);
        request ??= new ToolRequest();
        return tool switch
        {
            ToolId.AdjustImage => ImageStudio.Adjust(paths[0], request, cancellation),
            ToolId.CropImage => ImageStudio.Crop(paths[0], request, cancellation),
            ToolId.CompressImage => Many(paths, path => ImageStudio.Compress(path, request, cancellation)),
            ToolId.AnnotateImage => ImageStudio.Annotate(paths[0], request, cancellation),
            ToolId.RedactImage => ImageStudio.Redact(paths[0], request, cancellation),
            ToolId.AddBackground => ImageStudio.AddBackground(paths[0], request, cancellation),
            ToolId.RemoveBackground => Many(paths, path => ImageStudio.RemoveBackground(path, cancellation)),
            ToolId.ResizeImage => ImageStudio.Resize(paths[0], request, cancellation),
            ToolId.RotateImage => ImageStudio.Rotate(paths[0], request, cancellation),
            ToolId.Collage => ImageStudio.Collage(paths, request, cancellation),
            ToolId.ImagesToPdf => PdfStudio.ImagesToPdf(paths, cancellation),
            ToolId.MergePdf => PdfStudio.Merge(paths, cancellation),
            ToolId.SplitPdf => PdfStudio.Split(paths[0], request, cancellation),
            ToolId.OrganizePdf => PdfStudio.Organize(paths[0], request, cancellation),
            ToolId.CompressPdf => Many(paths, path => PdfStudio.Compress(path, cancellation)),
            ToolId.TrimVideo => MediaStudio.Trim(paths[0], request, progress, cancellation),
            ToolId.CropVideo => MediaStudio.Crop(paths[0], request, progress, cancellation),
            ToolId.CompressVideo => Many(paths, path => MediaStudio.Compress(path, request, progress, cancellation)),
            ToolId.VideoSpeed => MediaStudio.Speed(paths[0], request, progress, cancellation),
            ToolId.MuteVideo => Many(paths, path => MediaStudio.Mute(path, progress, cancellation)),
            ToolId.VideoFrames => MediaStudio.Frames(paths[0], request, progress, cancellation),
            ToolId.SplitVideo => MediaStudio.Split(paths[0], request, progress, cancellation),
            ToolId.RedactVideo => MediaStudio.Redact(paths[0], request, progress, cancellation),
            ToolId.JoinVideos => MediaStudio.Join(paths, progress, cancellation),
            ToolId.TrimAudio => MediaStudio.TrimAudio(paths[0], request, cancellation),
            ToolId.NormalizeAudio => Many(paths, path => MediaStudio.Normalize(path, request, cancellation)),
            ToolId.AudioChannels => MediaStudio.Channels(paths[0], request, cancellation),
            ToolId.BleepAudio => MediaStudio.Bleep(paths[0], request, cancellation),
            ToolId.AudioToVideo => MediaStudio.Visualize(paths[0], request, progress, cancellation),
            ToolId.Metadata => MetadataStudio.Strip(paths[0], cancellation),
            ToolId.ReadQr => VisionStudio.Read(paths, cancellation),
            ToolId.Unzip => Many(paths, path => ArchiveStudio.Extract(path, cancellation)),
            _ => throw new OrangeException(OrangeErrorCode.Unsupported, tool.ToString())
        };
    }

    public static IReadOnlyList<MetadataStudio.Field> Metadata(string path) => MetadataStudio.Fields(path);

    public static Task<IReadOnlyList<string>> DownloadAsync(string raw, bool audioOnly, string directory, Action<double>? progress, CancellationToken cancellation) =>
        DownloadStudio.Download(raw, audioOnly, directory, progress, cancellation);

    public static IReadOnlyList<string> Zip(IReadOnlyList<string> paths, string? directory = null) =>
        [ArchiveStudio.Zip(paths, directory ?? OutputLocation.DirectoryBeside(paths[0]))];

    public static string Duplicate(string path)
    {
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path), Path.GetExtension(path).TrimStart('.'));
        File.Copy(path, destination);
        return destination;
    }

    public static string CopyTo(string path, string directory)
    {
        Directory.CreateDirectory(directory);
        var destination = UniqueDestination.Url(directory, OutputLocation.BaseName(path), Path.GetExtension(path).TrimStart('.'));
        File.Copy(path, destination);
        return destination;
    }

    public static string MoveTo(string path, string directory)
    {
        Directory.CreateDirectory(directory);
        var destination = UniqueDestination.Url(directory, OutputLocation.BaseName(path), Path.GetExtension(path).TrimStart('.'));
        File.Move(path, destination);
        return destination;
    }

    static async Task<IReadOnlyList<string>> Many(IReadOnlyList<string> paths, Func<string, Task<IReadOnlyList<string>>> body)
    {
        var results = new List<string>();
        foreach (var path in paths) results.AddRange(await body(path));
        return results;
    }
}
