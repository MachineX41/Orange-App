using System.Diagnostics;

namespace Orange;

public static class Ffmpeg
{
    public static string? Locate(string name)
    {
        var beside = Path.Combine(AppContext.BaseDirectory, OperatingSystem.IsWindows() ? name + ".exe" : name);
        if (File.Exists(beside)) return beside;
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var directory in path.Split(Path.PathSeparator))
        {
            var candidate = Path.Combine(directory, OperatingSystem.IsWindows() ? name + ".exe" : name);
            if (File.Exists(candidate)) return candidate;
        }
        foreach (var candidate in new[] { "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name, "/usr/bin/" + name })
        {
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }

    public static async Task RunAsync(IReadOnlyList<string> arguments, Action<double>? progress, CancellationToken cancellation)
    {
        var tool = Locate("ffmpeg") ?? throw new OrangeException(OrangeErrorCode.ToolFailed, Lang.T(
            "FFmpeg is required for video and audio. Place ffmpeg next to Orange or on PATH.",
            "Video ve ses için FFmpeg gerekli. ffmpeg’i Orange’ın yanına veya PATH’e koyun."));
        var start = new ProcessStartInfo(tool)
        {
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new OrangeException(OrangeErrorCode.ToolFailed, "ffmpeg");
        var error = await process.StandardError.ReadToEndAsync(cancellation);
        await process.WaitForExitAsync(cancellation);
        progress?.Invoke(1);
        if (process.ExitCode != 0)
            throw new OrangeException(OrangeErrorCode.ToolFailed, string.IsNullOrWhiteSpace(error) ? "ffmpeg" : error.Trim().Split('\n').Last());
    }

    public static async Task<(double Duration, int Width, int Height, bool Audio)> ProbeAsync(string path, CancellationToken cancellation)
    {
        var tool = Locate("ffprobe") ?? Locate("ffmpeg");
        if (tool is null) return (0, 0, 0, true);
        var ffmpegProbe = Path.GetFileName(tool).StartsWith("ffmpeg", StringComparison.OrdinalIgnoreCase);
        var start = new ProcessStartInfo(tool)
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        if (ffmpegProbe)
        {
            start.RedirectStandardError = true;
            start.ArgumentList.Add("-hide_banner");
            start.ArgumentList.Add("-i");
            start.ArgumentList.Add(path);
        }
        else
        {
            foreach (var argument in new[] { "-v", "error", "-show_entries", "format=duration:stream=width,height,codec_type", "-of", "default=nw=1", path })
                start.ArgumentList.Add(argument);
        }
        using var process = Process.Start(start);
        if (process is null) return (0, 0, 0, true);
        var stdout = process.StandardOutput.ReadToEndAsync(cancellation);
        var text = ffmpegProbe
            ? await process.StandardError.ReadToEndAsync(cancellation)
            : await stdout;
        if (ffmpegProbe) await stdout;
        await process.WaitForExitAsync(cancellation);
        double duration = 0;
        var width = 0;
        var height = 0;
        var audio = false;
        foreach (var line in text.Split('\n'))
        {
            var pair = line.Split('=', 2);
            if (pair.Length != 2) continue;
            if (pair[0] == "duration") double.TryParse(pair[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out duration);
            if (pair[0] == "width") int.TryParse(pair[1], out width);
            if (pair[0] == "height") int.TryParse(pair[1], out height);
            if (pair[0] == "codec_type" && pair[1].Trim() == "audio") audio = true;
        }
        if (ffmpegProbe)
        {
            var durationMatch = System.Text.RegularExpressions.Regex.Match(text, @"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)");
            if (durationMatch.Success)
                duration = int.Parse(durationMatch.Groups[1].Value) * 3600 + int.Parse(durationMatch.Groups[2].Value) * 60 + double.Parse(durationMatch.Groups[3].Value, System.Globalization.CultureInfo.InvariantCulture);
            var videoMatch = System.Text.RegularExpressions.Regex.Match(text, @"Video:.*? (\d{2,5})x(\d{2,5})");
            if (videoMatch.Success)
            {
                int.TryParse(videoMatch.Groups[1].Value, out width);
                int.TryParse(videoMatch.Groups[2].Value, out height);
            }
            audio = text.Contains("Audio:", StringComparison.Ordinal);
        }
        return (duration, width, height, audio);
    }
}
