namespace Orange;

public enum WheelMode
{
    Convert,
    Tools,
    Actions
}

public enum ActionId
{
    Float,
    Copy,
    Move,
    CopyPath,
    Duplicate,
    Reveal,
    Share,
    Zip,
    OpenTerminal
}

public enum AppearanceChoice
{
    System,
    Light,
    Dark
}

public enum AppSection
{
    Home,
    Library,
    Download,
    Shelf,
    ImageTools,
    VideoTools,
    AudioTools,
    PdfTools
}

public sealed class FileRef
{
    public required string Path { get; init; }
    public required string Name { get; init; }
    public required MediaKind Kind { get; init; }
    public required long ByteCount { get; init; }
    public string Id => Path;
    public bool Exists => File.Exists(Path) || Directory.Exists(Path);

    public static FileRef? Load(string path)
    {
        var full = System.IO.Path.GetFullPath(path);
        if (!File.Exists(full) && !Directory.Exists(full)) return null;
        var directory = Directory.Exists(full);
        long size = 0;
        if (!directory)
        {
            try { size = new FileInfo(full).Length; } catch { size = 0; }
        }
        return new FileRef
        {
            Path = full,
            Name = System.IO.Path.GetFileName(full),
            Kind = directory ? MediaKind.Other : Catalog.Kind(full),
            ByteCount = size
        };
    }
}

public enum JobState
{
    Running,
    Success,
    Failure
}

public sealed class JobRecord
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public required string Title { get; init; }
    public string Detail { get; set; } = "";
    public string Symbol { get; init; } = "";
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.Now;
    public JobState State { get; set; } = JobState.Running;
    public List<string> OutputPaths { get; } = [];
}

public static class OutputLocation
{
    public static string? CustomDirectory { get; set; }

    public static string DirectoryBeside(string source)
    {
        if (!string.IsNullOrEmpty(CustomDirectory)) return CustomDirectory;
        var parent = Path.GetDirectoryName(source);
        if (!string.IsNullOrEmpty(parent) && IsWritable(parent)) return parent;
        return Downloads();
    }

    public static string Downloads()
    {
        var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        if (Directory.Exists(downloads)) return downloads;
        return Path.GetTempPath();
    }

    public static string BaseName(string path, string? suffix = null)
    {
        var baseName = Path.GetFileNameWithoutExtension(path);
        if (string.IsNullOrEmpty(suffix)) return baseName;
        return $"{baseName} {suffix}";
    }

    static bool IsWritable(string directory)
    {
        try
        {
            var probe = Path.Combine(directory, ".orange-write-" + Guid.NewGuid().ToString("N"));
            using (File.Create(probe)) { }
            File.Delete(probe);
            return true;
        }
        catch
        {
            return false;
        }
    }
}

public static class UniqueDestination
{
    public static string Url(string directory, string baseName, string extension)
    {
        var cleaned = Sanitize(baseName);
        string Candidate(string suffix)
        {
            var name = string.IsNullOrEmpty(suffix) ? cleaned : $"{cleaned} {suffix}";
            if (string.IsNullOrEmpty(extension)) return Path.Combine(directory, name);
            return Path.Combine(directory, name + "." + extension.TrimStart('.'));
        }
        var next = Candidate("");
        var index = 2;
        while (File.Exists(next) || Directory.Exists(next))
        {
            next = Candidate(index.ToString());
            index++;
        }
        return next;
    }

    public static string Folder(string directory, string baseName)
    {
        var cleaned = Sanitize(baseName);
        var candidate = Path.Combine(directory, cleaned);
        var index = 2;
        while (File.Exists(candidate) || Directory.Exists(candidate))
        {
            candidate = Path.Combine(directory, $"{cleaned} {index}");
            index++;
        }
        return candidate;
    }

    public static string WriteText(string text, string beside)
    {
        var destination = Url(OutputLocation.DirectoryBeside(beside), OutputLocation.BaseName(beside), "txt");
        try
        {
            File.WriteAllText(destination, text);
        }
        catch
        {
            throw new OrangeException(OrangeErrorCode.WriteFailed, Path.GetFileName(destination));
        }
        return destination;
    }

    static string Sanitize(string name)
    {
        var trimmed = name.Trim();
        var stripped = string.IsNullOrEmpty(trimmed) ? "Orange" : trimmed;
        return stripped.Replace('/', '-').Replace(':', '-');
    }
}
