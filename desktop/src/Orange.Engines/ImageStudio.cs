using ImageMagick;

namespace Orange;

public static class ImageStudio
{
    public static Task<IReadOnlyList<string>> Convert(string path, ConvertTarget target, double quality, CancellationToken cancellation) =>
        Task.FromResult<IReadOnlyList<string>>([Write(Load(path), path, target, quality, null)]);

    public static Task<IReadOnlyList<string>> Adjust(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var image = Load(path);
        var values = request.Adjust;
        if (values.Exposure != 0) image.Evaluate(Channels.RGB, EvaluateOperator.Multiply, 1 + values.Exposure);
        if (values.Brightness != 0) image.Evaluate(Channels.RGB, EvaluateOperator.Add, values.Brightness * Quantum.Max * 0.25);
        if (values.Contrast != 0) image.SigmoidalContrast(Math.Abs(values.Contrast) * 4 + 1, new Percentage(50));
        if (values.Saturation != 0 || values.Vibrance != 0)
            image.Modulate(new Percentage(100), new Percentage(100 + (values.Saturation + values.Vibrance * 0.6) * 100));
        if (values.Warmth != 0 || values.Tint != 0)
            image.Modulate(new Percentage(100), new Percentage(100), new Percentage(100 + values.Warmth * 12 - values.Tint * 6));
        if (values.Highlights != 0 || values.Shadows != 0)
            image.Level(new Percentage(Math.Max(0, -values.Shadows) * 20), new Percentage(100 - Math.Max(0, values.Highlights) * 20));
        if (values.Sharpness > 0) image.UnsharpMask(1.2, 0.8, values.Sharpness * 2, 0.02);
        if (values.Vignette > 0) image.Vignette(values.Vignette, 0.6, 0, 0);
        return Task.FromResult<IReadOnlyList<string>>([Write(image, path, Same(path), 0.92, "adjusted")]);
    }

    public static Task<IReadOnlyList<string>> Crop(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var image = Load(path);
        var pixels = CropMath.PixelRectTopLeft(request.Crop, new Size(image.Width, image.Height));
        var geometry = new MagickGeometry((int)Math.Round(pixels.X), (int)Math.Round(pixels.Y), (uint)Math.Max(1, pixels.Width), (uint)Math.Max(1, pixels.Height));
        image.Crop(geometry);
        image.ResetPage();
        return Task.FromResult<IReadOnlyList<string>>([Write(image, path, Same(path), 0.92, "cropped")]);
    }

    public static Task<IReadOnlyList<string>> Compress(string path, ToolRequest request, CancellationToken cancellation)
    {
        var before = new FileInfo(path).Length;
        using var image = Load(path);
        image.Strip();
        var destination = Write(image, path, Same(path) == ConvertTarget.Png ? ConvertTarget.Jpeg : Same(path), Math.Clamp(request.Quality, 0.3, 0.9), "compressed");
        if (new FileInfo(destination).Length >= before)
        {
            File.Delete(destination);
            throw new OrangeException(OrangeErrorCode.NotSmaller);
        }
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> Annotate(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var image = Load(path);
        image.Settings.FontPointsize = Math.Max(18, image.Height / 18.0);
        image.Settings.FillColor = new MagickColor(request.Color);
        image.Annotate(string.IsNullOrWhiteSpace(request.Text) ? "Orange" : request.Text, Gravity.Northwest);
        return Task.FromResult<IReadOnlyList<string>>([Write(image, path, Same(path), 0.92, "marked")]);
    }

    public static Task<IReadOnlyList<string>> Redact(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var image = Load(path);
        foreach (var region in request.Regions)
        {
            var pixels = CropMath.PixelRectTopLeft(region, new Size(image.Width, image.Height));
            var geometry = new MagickGeometry((int)pixels.X, (int)pixels.Y, (uint)Math.Max(1, pixels.Width), (uint)Math.Max(1, pixels.Height));
            using var patch = image.CloneArea(geometry);
            switch (request.RedactStyle)
            {
                case "blur":
                    patch.GaussianBlur(Math.Max(8, Math.Min(patch.Width, patch.Height) / 6.0));
                    break;
                case "solid":
                    patch.Colorize(new MagickColor("#101113"), new Percentage(100));
                    break;
                default:
                    var scale = (uint)Math.Max(1, Math.Min(patch.Width, patch.Height) / 12);
                    patch.Scale(scale, scale);
                    patch.Scale(patch.Width * (uint)Math.Max(1, pixels.Width) / Math.Max(1, patch.Width), patch.Height);
                    patch.Resize((uint)Math.Max(1, pixels.Width), (uint)Math.Max(1, pixels.Height));
                    break;
            }
            image.Composite(patch, geometry.X, geometry.Y, CompositeOperator.SrcOver);
        }
        return Task.FromResult<IReadOnlyList<string>>([Write(image, path, Same(path), 0.92, "redacted")]);
    }

    public static Task<IReadOnlyList<string>> AddBackground(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var image = Load(path);
        using var canvas = new MagickImage(new MagickColor(request.Background), image.Width, image.Height);
        canvas.Composite(image, Gravity.Center, CompositeOperator.SrcOver);
        return Task.FromResult<IReadOnlyList<string>>([Write(canvas, path, ConvertTarget.Png, 1, "background")]);
    }

    public static async Task<IReadOnlyList<string>> RemoveBackground(string path, CancellationToken cancellation)
    {
        using var image = Load(path);
        var mask = await VisionStudio.SubjectMaskAsync(image, cancellation);
        if (mask is null) throw new OrangeException(OrangeErrorCode.NoSubject);
        using (mask)
        {
            image.HasAlpha = true;
            image.Composite(mask, CompositeOperator.CopyAlpha);
        }
        return [Write(image, path, ConvertTarget.Png, 1, "cutout")];
    }

    public static Task<IReadOnlyList<string>> Resize(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var image = Load(path);
        var width = request.Width > 0 ? (uint)request.Width : image.Width;
        var height = request.Height > 0 ? (uint)request.Height : image.Height;
        image.Resize(width, height);
        return Task.FromResult<IReadOnlyList<string>>([Write(image, path, Same(path), 0.92, "resized")]);
    }

    public static Task<IReadOnlyList<string>> Rotate(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var image = Load(path);
        var turns = ((request.QuartersClockwise % 4) + 4) % 4;
        if (turns != 0) image.Rotate(turns * 90);
        if (request.FlipHorizontal) image.Flop();
        if (request.FlipVertical) image.Flip();
        return Task.FromResult<IReadOnlyList<string>>([Write(image, path, Same(path), 0.92, "rotated")]);
    }

    public static Task<IReadOnlyList<string>> Collage(IReadOnlyList<string> paths, ToolRequest request, CancellationToken cancellation)
    {
        if (paths.Count < 2) throw new OrangeException(OrangeErrorCode.Empty);
        var images = paths.Select(Load).ToList();
        try
        {
            var columns = request.Columns > 0 ? Math.Min(request.Columns, images.Count) : (int)Math.Ceiling(Math.Sqrt(images.Count));
            var rows = (int)Math.Ceiling(images.Count / (double)columns);
            const int width = 2400;
            var gap = (int)(width * 0.02);
            var cellWidth = (width - gap * (columns + 1)) / columns;
            var cellHeight = cellWidth;
            var height = cellHeight * rows + gap * (rows + 1);
            using var canvas = new MagickImage(MagickColors.White, (uint)width, (uint)height);
            for (var index = 0; index < images.Count; index++)
            {
                var image = images[index];
                image.Resize(new MagickGeometry((uint)cellWidth, (uint)cellHeight) { FillArea = true });
                image.Crop((uint)cellWidth, (uint)cellHeight, Gravity.Center);
                var row = index / columns;
                var column = index % columns;
                canvas.Composite(image, gap + column * (cellWidth + gap), gap + row * (cellHeight + gap), CompositeOperator.SrcOver);
            }
            var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(paths[0]), Lang.T("Collage", "Kolaj"), "jpg");
            canvas.Quality = 92;
            canvas.Write(destination);
            return Task.FromResult<IReadOnlyList<string>>([destination]);
        }
        finally
        {
            foreach (var image in images) image.Dispose();
        }
    }

    public static MagickImage Load(string path)
    {
        try
        {
            var image = new MagickImage(path);
            image.AutoOrient();
            return image;
        }
        catch
        {
            throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path));
        }
    }

    public static string Write(MagickImage image, string source, ConvertTarget target, double quality, string? suffix)
    {
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(source), OutputLocation.BaseName(source, suffix), target.FileExtension());
        image.Quality = (uint)Math.Clamp(quality * 100, 1, 100);
        try
        {
            image.Write(destination, Format(target));
        }
        catch
        {
            throw new OrangeException(OrangeErrorCode.WriteFailed, Path.GetFileName(destination));
        }
        return destination;
    }

    public static ConvertTarget Same(string path) => Catalog.CanonicalExtension(Path.GetExtension(path)) switch
    {
        "png" => ConvertTarget.Png,
        "heic" => ConvertTarget.Heic,
        "webp" => ConvertTarget.Webp,
        "avif" => ConvertTarget.Avif,
        "tiff" => ConvertTarget.Tiff,
        "bmp" => ConvertTarget.Bmp,
        "gif" => ConvertTarget.Gif,
        _ => ConvertTarget.Jpeg
    };

    static MagickFormat Format(ConvertTarget target) => target switch
    {
        ConvertTarget.Png => MagickFormat.Png,
        ConvertTarget.Heic => MagickFormat.Heic,
        ConvertTarget.Webp => MagickFormat.WebP,
        ConvertTarget.Avif => MagickFormat.Avif,
        ConvertTarget.Tiff => MagickFormat.Tiff,
        ConvertTarget.Bmp => MagickFormat.Bmp,
        ConvertTarget.Gif => MagickFormat.Gif,
        ConvertTarget.Pdf => MagickFormat.Pdf,
        _ => MagickFormat.Jpeg
    };
}
