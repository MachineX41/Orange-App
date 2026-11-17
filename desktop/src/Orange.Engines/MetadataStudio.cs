using ImageMagick;

namespace Orange;

public static class MetadataStudio
{
    public sealed record Field(string Key, string Value);

    public static IReadOnlyList<Field> Fields(string path)
    {
        var kind = Catalog.Kind(path);
        try
        {
            if (kind == MediaKind.Image)
            {
                using var image = new MagickImage(path);
                var profile = image.GetExifProfile();
                var fields = new List<Field>
                {
                    new("pixel", $"{image.Width} × {image.Height}"),
                    new("format", image.Format.ToString())
                };
                if (profile is not null)
                {
                    foreach (var value in profile.Values.Take(24))
                        fields.Add(new Field(value.Tag.ToString(), value.ToString() ?? ""));
                }
                return fields;
            }
            if (kind == MediaKind.Pdf)
            {
                using var document = UglyToad.PdfPig.PdfDocument.Open(path);
                var info = document.Information;
                return
                [
                    new Field("pages", document.NumberOfPages.ToString()),
                    new Field("title", info.Title ?? ""),
                    new Field("author", info.Author ?? "")
                ];
            }
            return [new Field("name", Path.GetFileName(path)), new Field("bytes", new FileInfo(path).Length.ToString())];
        }
        catch
        {
            return [new Field("name", Path.GetFileName(path))];
        }
    }

    public static async Task<IReadOnlyList<string>> Strip(string path, CancellationToken cancellation)
    {
        var kind = Catalog.Kind(path);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "clean"), Path.GetExtension(path).TrimStart('.'));
        if (kind == MediaKind.Image)
        {
            using var image = new MagickImage(path);
            image.Strip();
            image.Write(destination);
            return [destination];
        }
        if (kind is MediaKind.Video or MediaKind.Audio)
        {
            await Ffmpeg.RunAsync(["-y", "-i", path, "-map_metadata", "-1", "-c", "copy", destination], null, cancellation);
            return [destination];
        }
        if (kind == MediaKind.Pdf)
        {
            File.Copy(path, destination);
            return [destination];
        }
        throw new OrangeException(OrangeErrorCode.Unsupported, Path.GetExtension(path));
    }
}
