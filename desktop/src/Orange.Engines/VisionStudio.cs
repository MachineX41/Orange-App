using System.Diagnostics;
using ImageMagick;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using OpenCvSharp;
using SkiaSharp;
using ZXing;
using ZXing.SkiaSharp;

namespace Orange;

public static class VisionStudio
{
    public sealed record Hit(string Source, int? Page, string Symbology, string Payload, CodeAction Action);

    public static Task<IReadOnlyList<string>> Read(IReadOnlyList<string> paths, CancellationToken cancellation)
    {
        var hits = paths.SelectMany(Scan).ToList();
        if (hits.Count == 0) throw new OrangeException(OrangeErrorCode.NothingFound);
        var lines = hits.Select(hit =>
        {
            var destination = hit.Action.Destination;
            var insecure = hit.Action.IsInsecure ? " http" : "";
            return $"{hit.Source}\t{hit.Symbology}\t{hit.Payload}\t{destination}{insecure}";
        });
        return Task.FromResult<IReadOnlyList<string>>([UniqueDestination.WriteText(string.Join("\n", lines), paths[0])]);
    }

    public static IReadOnlyList<Hit> Scan(string path)
    {
        if (Catalog.Kind(path) == MediaKind.Pdf)
        {
            var bytes = File.ReadAllBytes(path);
            var count = PDFtoImage.Conversion.GetPageCount(bytes);
            var hits = new List<Hit>();
            for (var index = 0; index < count; index++)
            {
                using var bitmap = PDFtoImage.Conversion.ToImage(bytes, index);
                hits.AddRange(Decode(bitmap, Path.GetFileName(path), index + 1));
            }
            return hits;
        }
        using var image = SKBitmap.Decode(path);
        return image is null ? [] : Decode(image, Path.GetFileName(path), null).ToArray();
    }

    public static Task<string> RecognizeAsync(string path, CancellationToken cancellation)
    {
        var tool = Ffmpeg.Locate("tesseract");
        if (tool is null) return Task.FromResult("");
        var start = new ProcessStartInfo(tool, $"{Quote(path)} stdout")
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var process = Process.Start(start);
        if (process is null) return Task.FromResult("");
        var text = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return Task.FromResult(text.Trim());
    }

    public static IReadOnlyList<Rect> Faces(string path)
    {
        var cascadePath = Resolve("haarcascade_frontalface_default.xml");
        if (cascadePath is null) return [];
        try
        {
            using var image = Cv2.ImRead(path);
            if (image.Empty()) return [];
            using var gray = new Mat();
            Cv2.CvtColor(image, gray, ColorConversionCodes.BGR2GRAY);
            using var cascade = new CascadeClassifier(cascadePath);
            var faces = cascade.DetectMultiScale(gray, 1.1, 4, HaarDetectionTypes.ScaleImage, new OpenCvSharp.Size(40, 40));
            return faces.Select(face => new Rect(face.X / (double)image.Width, face.Y / (double)image.Height, face.Width / (double)image.Width, face.Height / (double)image.Height)).ToArray();
        }
        catch
        {
            return [];
        }
    }

    public static IReadOnlyList<Rect> TextRegions(string path)
    {
        var tool = Ffmpeg.Locate("tesseract");
        if (tool is null) return [];
        var start = new ProcessStartInfo(tool)
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        start.ArgumentList.Add(path);
        start.ArgumentList.Add("stdout");
        start.ArgumentList.Add("tsv");
        using var process = Process.Start(start);
        if (process is null) return [];
        var table = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        using var image = Cv2.ImRead(path);
        var width = image.Empty() ? 1 : image.Width;
        var height = image.Empty() ? 1 : image.Height;
        var regions = new List<Rect>();
        foreach (var line in table.Split('\n').Skip(1))
        {
            var cells = line.Split('\t');
            if (cells.Length < 12) continue;
            if (!int.TryParse(cells[6], out var left) || !int.TryParse(cells[7], out var top)) continue;
            if (!int.TryParse(cells[8], out var boxWidth) || !int.TryParse(cells[9], out var boxHeight)) continue;
            if (boxWidth < 8 || boxHeight < 8) continue;
            regions.Add(new Rect(left / (double)width, top / (double)height, boxWidth / (double)width, boxHeight / (double)height));
        }
        return regions;
    }

    public static Task<MagickImage?> SubjectMaskAsync(MagickImage image, CancellationToken cancellation)
    {
        var model = Resolve("u2netp.onnx");
        if (model is null) return Task.FromResult<MagickImage?>(null);
        const int side = 320;
        using var resized = image.Clone();
        resized.Resize((uint)side, (uint)side);
        resized.ColorSpace = ColorSpace.sRGB;
        var pixels = resized.GetPixels().ToByteArray(PixelMapping.RGB) ?? [];
        var tensor = new DenseTensor<float>([1, 3, side, side]);
        float[] mean = [0.485f, 0.456f, 0.406f];
        float[] std = [0.229f, 0.224f, 0.225f];
        for (var y = 0; y < side; y++)
        {
            for (var x = 0; x < side; x++)
            {
                var offset = (y * side + x) * 3;
                for (var channel = 0; channel < 3; channel++)
                    tensor[0, channel, y, x] = (pixels[offset + channel] / 255f - mean[channel]) / std[channel];
            }
        }
        using var session = new InferenceSession(model);
        var inputName = session.InputMetadata.Keys.First();
        using var results = session.Run([NamedOnnxValue.CreateFromTensor(inputName, tensor)]);
        var output = results.First().AsTensor<float>();
        var mask = new byte[side * side];
        float max = 0;
        for (var index = 0; index < mask.Length; index++) max = Math.Max(max, output.GetValue(index));
        if (max < 0.05) return Task.FromResult<MagickImage?>(null);
        for (var index = 0; index < mask.Length; index++) mask[index] = (byte)Math.Clamp(output.GetValue(index) / max * 255, 0, 255);
        var rgb = new byte[mask.Length * 3];
        for (var index = 0; index < mask.Length; index++)
        {
            rgb[index * 3] = mask[index];
            rgb[index * 3 + 1] = mask[index];
            rgb[index * 3 + 2] = mask[index];
        }
        var magick = new MagickImage(MagickColor.FromRgba(255, 255, 255, 0), (uint)image.Width, (uint)image.Height);
        using var small = new MagickImage(MagickColors.Black, (uint)side, (uint)side);
        small.ReadPixels(rgb, new PixelReadSettings((uint)side, (uint)side, StorageType.Char, PixelMapping.RGB));
        small.Resize(image.Width, image.Height);
        magick.Composite(small, CompositeOperator.CopyAlpha);
        return Task.FromResult<MagickImage?>(magick);
    }

    static IEnumerable<Hit> Decode(SKBitmap bitmap, string source, int? page)
    {
        var reader = new BarcodeReader { AutoRotate = true, Options = { TryHarder = true } };
        var results = reader.DecodeMultiple(bitmap) ?? [];
        return results.Where(result => !string.IsNullOrEmpty(result.Text)).Select(result =>
            new Hit(source, page, result.BarcodeFormat.ToString(), result.Text, CodeAction.Parse(result.Text)));
    }

    public static string? Resolve(string file)
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "models", file),
            Path.Combine(AppContext.BaseDirectory, file),
            Path.Combine(Directory.GetCurrentDirectory(), "models", file)
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    static string Quote(string path) => "\"" + path + "\"";
}
