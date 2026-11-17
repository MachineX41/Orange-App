using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;
using SkiaSharp;
using UglyToad.PdfPig;

namespace Orange;

public static class PdfStudio
{
    public static Task<IReadOnlyList<string>> ImagesToPdf(IReadOnlyList<string> paths, CancellationToken cancellation)
    {
        if (paths.Count == 0) throw new OrangeException(OrangeErrorCode.Empty);
        var destination = UniqueDestination.Url(
            OutputLocation.DirectoryBeside(paths[0]),
            paths.Count == 1 ? OutputLocation.BaseName(paths[0]) : Lang.T("Images", "Görseller"),
            "pdf");
        using var document = SKDocument.CreatePdf(destination);
        foreach (var path in paths)
        {
            using var bitmap = SKBitmap.Decode(path) ?? throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path));
            using var canvas = document.BeginPage(bitmap.Width, bitmap.Height);
            canvas.DrawBitmap(bitmap, 0, 0);
            document.EndPage();
        }
        document.Close();
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> Merge(IReadOnlyList<string> paths, CancellationToken cancellation)
    {
        if (paths.Count < 2) throw new OrangeException(OrangeErrorCode.Empty);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(paths[0]), Lang.T("Merged", "Birleşik"), "pdf");
        using var output = new PdfSharp.Pdf.PdfDocument();
        foreach (var path in paths)
        {
            using var input = Open(path);
            for (var index = 0; index < input.PageCount; index++) output.AddPage(input.Pages[index]);
        }
        output.Save(destination);
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> Split(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var input = Open(path);
        var results = new List<string>();
        if (request.SplitKind == "chunks")
        {
            var size = Math.Max(1, request.ChunkSize);
            for (var start = 0; start < input.PageCount; start += size)
            {
                using var output = new PdfSharp.Pdf.PdfDocument();
                for (var index = start; index < Math.Min(start + size, input.PageCount); index++) output.AddPage(input.Pages[index]);
                var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, (results.Count + 1).ToString()), "pdf");
                output.Save(destination);
                results.Add(destination);
            }
        }
        else if (request.SplitKind == "ranges")
        {
            foreach (var (start, end) in PageSelection.Parse(request.PageSelection, input.PageCount))
            {
                using var output = new PdfSharp.Pdf.PdfDocument();
                for (var page = start; page <= end; page++) output.AddPage(input.Pages[page - 1]);
                var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, $"{start}-{end}"), "pdf");
                output.Save(destination);
                results.Add(destination);
            }
        }
        else
        {
            for (var index = 0; index < input.PageCount; index++)
            {
                using var output = new PdfSharp.Pdf.PdfDocument();
                output.AddPage(input.Pages[index]);
                var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, (index + 1).ToString()), "pdf");
                output.Save(destination);
                results.Add(destination);
            }
        }
        return Task.FromResult<IReadOnlyList<string>>(results);
    }

    public static Task<IReadOnlyList<string>> Organize(string path, ToolRequest request, CancellationToken cancellation)
    {
        using var input = Open(path);
        var order = string.IsNullOrWhiteSpace(request.PageOrder)
            ? Enumerable.Range(1, input.PageCount).ToArray()
            : request.PageOrder.Split(',', ';').Select(piece => int.Parse(piece.Trim())).ToArray();
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "ordered"), "pdf");
        using var output = new PdfSharp.Pdf.PdfDocument();
        foreach (var number in order)
        {
            if (number < 1 || number > input.PageCount) throw new OrangeException(OrangeErrorCode.InvalidPages);
            var page = output.AddPage(input.Pages[number - 1]);
            if (request.QuartersClockwise != 0) page.Rotate = (page.Rotate + request.QuartersClockwise * 90) % 360;
        }
        output.Save(destination);
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> Compress(string path, CancellationToken cancellation)
    {
        var before = new FileInfo(path).Length;
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, "compressed"), "pdf");
        var bytes = File.ReadAllBytes(path);
        var count = PDFtoImage.Conversion.GetPageCount(bytes);
        using var document = SKDocument.CreatePdf(destination);
        for (var index = 0; index < count; index++)
        {
            using var bitmap = PDFtoImage.Conversion.ToImage(bytes, index);
            using var canvas = document.BeginPage(bitmap.Width, bitmap.Height);
            canvas.DrawBitmap(bitmap, 0, 0);
            document.EndPage();
        }
        document.Close();
        if (new FileInfo(destination).Length >= before)
        {
            File.Delete(destination);
            throw new OrangeException(OrangeErrorCode.NotSmaller);
        }
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<IReadOnlyList<string>> ToImages(string path, ConvertTarget target, Action<double>? progress, CancellationToken cancellation)
    {
        var bytes = File.ReadAllBytes(path);
        var count = PDFtoImage.Conversion.GetPageCount(bytes);
        var results = new List<string>();
        for (var index = 0; index < count; index++)
        {
            cancellation.ThrowIfCancellationRequested();
            using var bitmap = PDFtoImage.Conversion.ToImage(bytes, index);
            using var data = bitmap.Encode(target == ConvertTarget.Png ? SKEncodedImageFormat.Png : target == ConvertTarget.Webp ? SKEncodedImageFormat.Webp : SKEncodedImageFormat.Jpeg, 90);
            var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path, (index + 1).ToString()), target.FileExtension());
            using var stream = File.Create(destination);
            data.SaveTo(stream);
            results.Add(destination);
            progress?.Invoke((index + 1) / (double)count);
        }
        return Task.FromResult<IReadOnlyList<string>>(results);
    }

    public static string Text(string path)
    {
        try
        {
            using var document = UglyToad.PdfPig.PdfDocument.Open(path);
            return string.Join("\n\n", document.GetPages().Select(page => page.Text));
        }
        catch
        {
            throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path));
        }
    }

    public static int PageCount(string path)
    {
        using var document = UglyToad.PdfPig.PdfDocument.Open(path);
        return document.NumberOfPages;
    }

    static PdfSharp.Pdf.PdfDocument Open(string path)
    {
        try
        {
            return PdfReader.Open(path, PdfDocumentOpenMode.Import);
        }
        catch
        {
            throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path));
        }
    }
}
