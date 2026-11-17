using System.Diagnostics;

namespace Orange;

public static class DownloadStudio
{
    static readonly HashSet<string> MediaExtensions =
    [
        "mp4", "mov", "m4v", "webm", "mkv", "mp3", "m4a", "wav", "aac", "flac", "ogg",
        "jpg", "jpeg", "png", "gif", "webp", "heic", "pdf", "zip"
    ];

    public static async Task<IReadOnlyList<string>> Download(string raw, bool audioOnly, string directory, Action<double>? progress, CancellationToken cancellation)
    {
        var url = LinkDiscovery.Normalize(raw);
        Directory.CreateDirectory(directory);
        if (MediaExtensions.Contains(Path.GetExtension(url.AbsolutePath).TrimStart('.').ToLowerInvariant()))
            return [await Fetch(url, directory, progress, false, cancellation)];
        var tool = Ffmpeg.Locate("yt-dlp");
        if (tool is not null) return await RunDownloader(tool, url, audioOnly, directory, progress, cancellation);
        using var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Orange/0.3.5");
        var html = await client.GetStringAsync(url, cancellation);
        var media = LinkDiscovery.MediaLink(html, url) ?? throw new OrangeException(OrangeErrorCode.NeedsDownloader);
        return [await Fetch(media, directory, progress, true, cancellation)];
    }

    static async Task<string> Fetch(Uri url, string directory, Action<double>? progress, bool rejectPages, CancellationToken cancellation)
    {
        using var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Orange/0.3.5");
        using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellation);
        if (!response.IsSuccessStatusCode) throw new OrangeException(OrangeErrorCode.BadLink);
        if (rejectPages && LinkDiscovery.IsPage(response.Content.Headers.ContentType?.MediaType))
            throw new OrangeException(OrangeErrorCode.NeedsDownloader);
        var name = response.Content.Headers.ContentDisposition?.FileNameStar
            ?? response.Content.Headers.ContentDisposition?.FileName
            ?? Path.GetFileName(url.LocalPath);
        name = name.Trim('"');
        if (string.IsNullOrEmpty(name)) name = "Download.bin";
        var destination = UniqueDestination.Url(directory, Path.GetFileNameWithoutExtension(name), Path.GetExtension(name).TrimStart('.'));
        var expected = response.Content.Headers.ContentLength ?? 0;
        await using var input = await response.Content.ReadAsStreamAsync(cancellation);
        await using var output = File.Create(destination);
        var buffer = new byte[256 * 1024];
        long received = 0;
        while (true)
        {
            var count = await input.ReadAsync(buffer, cancellation);
            if (count == 0) break;
            await output.WriteAsync(buffer.AsMemory(0, count), cancellation);
            received += count;
            if (expected > 0) progress?.Invoke(Math.Min(0.99, received / (double)expected));
        }
        progress?.Invoke(1);
        return destination;
    }

    static async Task<IReadOnlyList<string>> RunDownloader(string tool, Uri url, bool audioOnly, string directory, Action<double>? progress, CancellationToken cancellation)
    {
        var start = new ProcessStartInfo(tool)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = directory
        };
        start.ArgumentList.Add("--newline");
        start.ArgumentList.Add("--retries");
        start.ArgumentList.Add("10");
        start.ArgumentList.Add("--fragment-retries");
        start.ArgumentList.Add("10");
        start.ArgumentList.Add("--extractor-retries");
        start.ArgumentList.Add("3");
        if (IsYouTube(url) && CanImpersonateChrome(tool))
        {
            start.ArgumentList.Add("--impersonate");
            start.ArgumentList.Add("chrome");
        }
        start.ArgumentList.Add("-o");
        start.ArgumentList.Add("%(title)s.%(ext)s");
        if (audioOnly)
        {
            start.ArgumentList.Add("-x");
            start.ArgumentList.Add("--audio-format");
            start.ArgumentList.Add("m4a");
        }
        start.ArgumentList.Add(url.AbsoluteUri);
        using var process = Process.Start(start) ?? throw new OrangeException(OrangeErrorCode.ToolFailed, "yt-dlp");
        var reader = new DownloadProgressReader();
        while (true)
        {
            var line = await process.StandardError.ReadLineAsync(cancellation);
            if (line is null) break;
            foreach (var update in reader.Feed(line + "\n")) progress?.Invoke(update);
        }
        await process.WaitForExitAsync(cancellation);
        if (process.ExitCode != 0) throw new OrangeException(OrangeErrorCode.ToolFailed, "yt-dlp");
        var newest = new DirectoryInfo(directory).EnumerateFiles().OrderByDescending(file => file.LastWriteTimeUtc).FirstOrDefault();
        return newest is null ? [] : [newest.FullName];
    }

    static bool IsYouTube(Uri url)
    {
        var host = url.Host.ToLowerInvariant();
        if (host == "youtu.be" || host.EndsWith(".youtu.be", StringComparison.Ordinal)) return true;
        if (host == "youtube.com" || host.EndsWith(".youtube.com", StringComparison.Ordinal)) return true;
        return host == "youtube-nocookie.com" || host.EndsWith(".youtube-nocookie.com", StringComparison.Ordinal);
    }

    static bool? chromeImpersonation;

    static bool CanImpersonateChrome(string tool)
    {
        if (chromeImpersonation is { } cached) return cached;
        try
        {
            var start = new ProcessStartInfo(tool, "--list-impersonate-targets")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var process = Process.Start(start);
            if (process is null)
            {
                chromeImpersonation = false;
                return false;
            }
            var text = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            chromeImpersonation = text.Contains("chrome", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            chromeImpersonation = false;
        }
        return chromeImpersonation == true;
    }
}
