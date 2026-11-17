using System.IO.Compression;

namespace Orange;

public static class ArchiveStudio
{
    public static string Zip(IReadOnlyList<string> paths, string directory)
    {
        if (paths.Count == 0) throw new OrangeException(OrangeErrorCode.Empty);
        var baseName = paths.Count == 1 ? OutputLocation.BaseName(paths[0]) : "Archive";
        var destination = UniqueDestination.Url(directory, baseName, "zip");
        using (var archive = ZipFile.Open(destination, ZipArchiveMode.Create))
        {
            var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var path in paths)
            {
                var name = Path.GetFileName(path);
                if (!used.Add(name)) throw new OrangeException(OrangeErrorCode.Unsupported, name);
                archive.CreateEntryFromFile(path, name);
            }
        }
        return destination;
    }

    public static Task<IReadOnlyList<string>> Extract(string path, CancellationToken cancellation)
    {
        var folder = UniqueDestination.Folder(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path));
        Directory.CreateDirectory(folder);
        try
        {
            var ext = Path.GetExtension(path).ToLowerInvariant();
            if (ext == ".zip") ExtractZip(path, folder);
            else if (ext is ".tar" or ".gz" or ".tgz" or ".bz2" or ".tbz" or ".tbz2" or ".xz" or ".txz") ExtractTar(path, folder);
            else ExtractExternal(path, folder);
            RejectUnsafe(folder);
        }
        catch
        {
            Directory.Delete(folder, true);
            throw;
        }
        return Task.FromResult<IReadOnlyList<string>>([folder]);
    }

    static void ExtractZip(string path, string folder)
    {
        using var archive = ZipFile.OpenRead(path);
        foreach (var entry in archive.Entries)
        {
            var destination = SafeJoin(folder, entry.FullName);
            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(destination);
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            entry.ExtractToFile(destination);
        }
    }

    static void ExtractTar(string path, string folder)
    {
        var tool = Ffmpeg.Locate("tar") ?? "/usr/bin/tar";
        if (!File.Exists(tool)) throw new OrangeException(OrangeErrorCode.Unsupported, Path.GetExtension(path));
        var start = new System.Diagnostics.ProcessStartInfo(tool, $"-xf \"{path}\" -C \"{folder}\"")
        {
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var process = System.Diagnostics.Process.Start(start) ?? throw new OrangeException(OrangeErrorCode.ToolFailed, "tar");
        process.WaitForExit();
        if (process.ExitCode != 0) throw new OrangeException(OrangeErrorCode.ToolFailed, "tar");
    }

    static void ExtractExternal(string path, string folder)
    {
        var tool = Ffmpeg.Locate("7z") ?? Ffmpeg.Locate("7zz");
        if (tool is null) throw new OrangeException(OrangeErrorCode.Unsupported, Path.GetExtension(path).TrimStart('.').ToUpperInvariant());
        var start = new System.Diagnostics.ProcessStartInfo(tool, $"x -y -o\"{folder}\" \"{path}\"")
        {
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var process = System.Diagnostics.Process.Start(start) ?? throw new OrangeException(OrangeErrorCode.ToolFailed, "7z");
        process.WaitForExit();
        if (process.ExitCode != 0) throw new OrangeException(OrangeErrorCode.ToolFailed, "7z");
    }

    static string SafeJoin(string root, string entry)
    {
        var relative = entry.Replace('\\', '/');
        if (relative.Contains("..", StringComparison.Ordinal) || Path.IsPathRooted(relative))
            throw new OrangeException(OrangeErrorCode.UnsafeArchive);
        var destination = Path.GetFullPath(Path.Combine(root, relative));
        var fullRoot = Path.GetFullPath(root);
        if (!destination.StartsWith(fullRoot + Path.DirectorySeparatorChar, StringComparison.Ordinal) && destination != fullRoot)
            throw new OrangeException(OrangeErrorCode.UnsafeArchive);
        return destination;
    }

    static void RejectUnsafe(string folder)
    {
        var root = Path.GetFullPath(folder);
        foreach (var file in Directory.EnumerateFileSystemEntries(folder, "*", SearchOption.AllDirectories))
        {
            var info = new FileInfo(file);
            if (info.LinkTarget is not null || info.Attributes.HasFlag(FileAttributes.ReparsePoint))
                throw new OrangeException(OrangeErrorCode.UnsafeArchive);
            var full = Path.GetFullPath(file);
            if (!full.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
                throw new OrangeException(OrangeErrorCode.UnsafeArchive);
        }
    }
}
