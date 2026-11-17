using System.Globalization;
using SkiaSharp;

namespace Orange;

public static class MediaStudio
{
    public static async Task<IReadOnlyList<string>> Convert(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation)
    {
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path), target.FileExtension());
        var arguments = new List<string> { "-y", "-i", path };
        switch (target)
        {
            case ConvertTarget.Gif:
                arguments.AddRange(["-vf", "fps=12,scale=480:-1:flags=lanczos", destination]);
                break;
            case ConvertTarget.M4a:
            case ConvertTarget.Wav:
            case ConvertTarget.Aiff:
                arguments.AddRange(["-vn", destination]);
                break;
            default:
                arguments.AddRange(["-c:v", "libx264", "-crf", "23", "-c:a", "aac", destination]);
                break;
        }
        await Ffmpeg.RunAsync(arguments, progress, cancellation);
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Trim(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var end = request.End > request.Start ? request.End : request.Start + 1;
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "trimmed"), Path.GetExtension(path).TrimStart('.'));
        await Ffmpeg.RunAsync(["-y", "-ss", Seconds(request.Start), "-to", Seconds(end), "-i", path, "-c", "copy", destination], progress, cancellation);
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Crop(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var probe = await Ffmpeg.ProbeAsync(path, cancellation);
        var pixels = CropMath.PixelRectTopLeft(request.Crop, new Size(Math.Max(2, probe.Width), Math.Max(2, probe.Height)));
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "cropped"), Path.GetExtension(path).TrimStart('.'));
        var filter = FormattableString.Invariant($"crop={Math.Max(2, (int)pixels.Width)}:{Math.Max(2, (int)pixels.Height)}:{(int)pixels.X}:{(int)pixels.Y}");
        await Ffmpeg.RunAsync(["-y", "-i", path, "-vf", filter, "-c:a", "copy", destination], progress, cancellation);
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Compress(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var crf = request.VideoQuality switch { "small" => "32", "high" => "18", _ => "23" };
        var scale = request.VideoQuality == "small" ? "scale=960:-2" : "scale=trunc(iw/2)*2:trunc(ih/2)*2";
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "compressed"), "mp4");
        var before = new FileInfo(path).Length;
        await Ffmpeg.RunAsync(["-y", "-i", path, "-vf", scale, "-c:v", "libx264", "-crf", crf, "-c:a", "aac", destination], progress, cancellation);
        if (new FileInfo(destination).Length >= before)
        {
            File.Delete(destination);
            throw new OrangeException(OrangeErrorCode.NotSmaller);
        }
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Speed(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var factor = request.Speed <= 0 ? 1 : request.Speed;
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "speed"), Path.GetExtension(path).TrimStart('.'));
        var video = FormattableString.Invariant($"setpts={1 / factor}*PTS");
        var audio = FormattableString.Invariant($"atempo={Math.Clamp(factor, 0.5, 2)}");
        await Ffmpeg.RunAsync(["-y", "-i", path, "-filter:v", video, "-filter:a", audio, destination], progress, cancellation);
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Mute(string path, Action<double>? progress, CancellationToken cancellation)
    {
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "silent"), Path.GetExtension(path).TrimStart('.'));
        await Ffmpeg.RunAsync(["-y", "-i", path, "-c:v", "copy", "-an", destination], progress, cancellation);
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Frames(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var time = request.Start;
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "frame"), "png");
        await Ffmpeg.RunAsync(["-y", "-ss", Seconds(time), "-i", path, "-frames:v", "1", destination], progress, cancellation);
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Split(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var probe = await Ffmpeg.ProbeAsync(path, cancellation);
        var cut = request.Start > 0 ? request.Start : probe.Duration / 2;
        var first = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "1"), Path.GetExtension(path).TrimStart('.'));
        var second = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "2"), Path.GetExtension(path).TrimStart('.'));
        await Ffmpeg.RunAsync(["-y", "-i", path, "-to", Seconds(cut), "-c", "copy", first], progress, cancellation);
        await Ffmpeg.RunAsync(["-y", "-ss", Seconds(cut), "-i", path, "-c", "copy", second], progress, cancellation);
        return [first, second];
    }

    public static async Task<IReadOnlyList<string>> Redact(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var probe = await Ffmpeg.ProbeAsync(path, cancellation);
        var filters = new List<string>();
        foreach (var region in request.Regions)
        {
            var pixels = CropMath.PixelRectTopLeft(region, new Size(Math.Max(2, probe.Width), Math.Max(2, probe.Height)));
            var box = FormattableString.Invariant($"{(int)pixels.X}:{(int)pixels.Y}:{Math.Max(2, (int)pixels.Width)}:{Math.Max(2, (int)pixels.Height)}");
            filters.Add(request.RedactStyle == "solid" ? $"drawbox={box}:color=black@1:t=fill" : $"delogo={box}");
        }
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "redacted"), Path.GetExtension(path).TrimStart('.'));
        await Ffmpeg.RunAsync(["-y", "-i", path, "-vf", string.Join(",", filters), "-c:a", "copy", destination], progress, cancellation);
        return [destination];
    }

    public static async Task<IReadOnlyList<string>> Join(IReadOnlyList<string> paths, Action<double>? progress, CancellationToken cancellation)
    {
        if (paths.Count < 2) throw new OrangeException(OrangeErrorCode.Empty);
        var list = Path.Combine(Path.GetTempPath(), "orange-join-" + Guid.NewGuid().ToString("N") + ".txt");
        await File.WriteAllLinesAsync(list, paths.Select(path => "file '" + path.Replace("'", "'\\''") + "'"), cancellation);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(paths[0]), Lang.T("Joined", "Birleşik"), "mp4");
        try
        {
            await Ffmpeg.RunAsync(["-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", destination], progress, cancellation);
        }
        finally
        {
            File.Delete(list);
        }
        return [destination];
    }

    public static Task<IReadOnlyList<string>> TrimAudio(string path, ToolRequest request, CancellationToken cancellation)
    {
        var clip = LoadAudio(path);
        var bounds = request.End > request.Start ? (request.Start, request.End) : clip.SilenceBounds();
        var trimmed = clip.Trimmed(bounds.Item1, bounds.Item2);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "trimmed"), "wav");
        trimmed.WriteWav(destination);
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> Normalize(string path, ToolRequest request, CancellationToken cancellation)
    {
        var clip = LoadAudio(path).NormalizedPeak(request.NormalizeDb);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "normalized"), "wav");
        clip.WriteWav(destination);
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> Channels(string path, ToolRequest request, CancellationToken cancellation)
    {
        var clip = LoadAudio(path).Remixed(request.ToMono, [1, 1]);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, request.ToMono ? "mono" : "stereo"), "wav");
        clip.WriteWav(destination);
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> Bleep(string path, ToolRequest request, CancellationToken cancellation)
    {
        var end = request.End > request.Start ? request.End : request.Start + 0.4;
        var clip = LoadAudio(path).Bleeped((request.Start, end), request.BleepTone);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "bleep"), "wav");
        clip.WriteWav(destination);
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static async Task<IReadOnlyList<string>> Visualize(string path, ToolRequest request, Action<double>? progress, CancellationToken cancellation)
    {
        var clip = LoadAudio(path);
        var peaks = clip.Peaks(64);
        var folder = Path.Combine(Path.GetTempPath(), "orange-vis-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        var frame = Path.Combine(folder, "frame.png");
        using (var bitmap = new SKBitmap(640, 360))
        using (var canvas = new SKCanvas(bitmap))
        {
            canvas.Clear(new SKColor(16, 16, 18));
            using var paint = new SKPaint { Color = new SKColor(242, 107, 29), IsAntialias = true };
            var slot = 640f / Math.Max(1, peaks.Length);
            for (var index = 0; index < peaks.Length; index++)
            {
                var height = 20 + peaks[index] * 260;
                canvas.DrawRoundRect(new SKRoundRect(new SKRect(index * slot + 2, 300 - height, index * slot + slot - 2, 300), 4), paint);
            }
            using var data = bitmap.Encode(SKEncodedImageFormat.Png, 100);
            using var stream = File.Create(frame);
            data.SaveTo(stream);
        }
        var wav = Path.Combine(folder, "audio.wav");
        clip.WriteWav(wav);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "visual"), "mp4");
        try
        {
            await Ffmpeg.RunAsync(["-y", "-loop", "1", "-i", frame, "-i", wav, "-c:v", "libx264", "-tune", "stillimage", "-c:a", "aac", "-shortest", "-pix_fmt", "yuv420p", destination], progress, cancellation);
        }
        finally
        {
            Directory.Delete(folder, true);
        }
        return [destination];
    }

    static AudioBuffer LoadAudio(string path)
    {
        if (Path.GetExtension(path).Equals(".wav", StringComparison.OrdinalIgnoreCase)) return AudioBuffer.ReadWav(path);
        throw new OrangeException(OrangeErrorCode.ToolFailed, Lang.T(
            "Convert this audio to WAV first, then edit it.",
            "Bu sesi önce WAV’a çevirin, sonra düzenleyin."));
    }

    static string Seconds(double value) => value.ToString("0.###", CultureInfo.InvariantCulture);
}
