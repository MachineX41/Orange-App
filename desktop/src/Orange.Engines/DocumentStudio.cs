using System.IO.Compression;
using System.Text;
using System.Xml.Linq;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using SkiaSharp;

namespace Orange;

public static class DocumentStudio
{
    public static Task<IReadOnlyList<string>> Convert(string path, ConvertTarget target, CancellationToken cancellation)
    {
        var paragraphs = Read(path);
        if (paragraphs.Count == 0) throw new OrangeException(OrangeErrorCode.NothingFound);
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path), target.FileExtension());
        switch (target)
        {
            case ConvertTarget.Txt:
                File.WriteAllText(destination, string.Join("\n\n", paragraphs));
                break;
            case ConvertTarget.Html:
                File.WriteAllText(destination, "<html><body>" + string.Join("", paragraphs.Select(paragraph => "<p>" + System.Net.WebUtility.HtmlEncode(paragraph) + "</p>")) + "</body></html>");
                break;
            case ConvertTarget.Rtf:
                File.WriteAllText(destination, "{\\rtf1\\ansi " + string.Join("\\par ", paragraphs.Select(EscapeRtf)) + "}");
                break;
            case ConvertTarget.Docx:
                WriteDocx(destination, paragraphs);
                break;
            case ConvertTarget.Odt:
                WriteOdt(destination, paragraphs);
                break;
            case ConvertTarget.Pdf:
                WritePdf(destination, paragraphs);
                break;
            default:
                throw new OrangeException(OrangeErrorCode.Unsupported, target.FileExtension().ToUpperInvariant());
        }
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static List<string> Read(string path)
    {
        var ext = Catalog.CanonicalExtension(Path.GetExtension(path));
        try
        {
            return ext switch
            {
                "docx" => ReadDocx(path),
                "html" => [System.Text.RegularExpressions.Regex.Replace(File.ReadAllText(path), "<[^>]+>", " ").Trim()],
                "rtf" => [System.Text.RegularExpressions.Regex.Replace(File.ReadAllText(path), @"\\par|\\[a-z]+\d*|[{}]", " ").Trim()],
                "odt" => ReadOdt(path),
                "pdf" => [PdfStudio.Text(path)],
                "txt" or "md" or "text" => File.ReadAllLines(path).ToList(),
                _ => throw new OrangeException(OrangeErrorCode.Unsupported, ext.ToUpperInvariant())
            };
        }
        catch (OrangeException)
        {
            throw;
        }
        catch
        {
            throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path));
        }
    }

    static List<string> ReadDocx(string path)
    {
        using var document = WordprocessingDocument.Open(path, false);
        var body = document.MainDocumentPart?.Document.Body;
        if (body is null) return [];
        return body.Elements<Paragraph>().Select(paragraph => paragraph.InnerText).Where(text => !string.IsNullOrWhiteSpace(text)).ToList();
    }

    static List<string> ReadOdt(string path)
    {
        using var zip = ZipFile.OpenRead(path);
        var entry = zip.GetEntry("content.xml") ?? throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path));
        using var stream = entry.Open();
        var xml = XDocument.Load(stream);
        return xml.Descendants().Where(element => element.Name.LocalName == "p").Select(element => element.Value).Where(text => text.Length > 0).ToList();
    }

    static void WriteDocx(string path, IReadOnlyList<string> paragraphs)
    {
        using var document = WordprocessingDocument.Create(path, WordprocessingDocumentType.Document);
        var main = document.AddMainDocumentPart();
        main.Document = new Document(new Body(paragraphs.Select(text => new Paragraph(new Run(new Text(text)))).ToArray()));
        main.Document.Save();
    }

    static void WriteOdt(string path, IReadOnlyList<string> paragraphs)
    {
        using var zip = ZipFile.Open(path, ZipArchiveMode.Create);
        WriteEntry(zip, "mimetype", "application/vnd.oasis.opendocument.text");
        var body = string.Join("", paragraphs.Select(paragraph => "<text:p>" + System.Net.WebUtility.HtmlEncode(paragraph) + "</text:p>"));
        WriteEntry(zip, "content.xml", """
            <?xml version="1.0" encoding="UTF-8"?>
            <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
              <office:body><office:text>
            """ + body + "</office:text></office:body></office:document-content>");
    }

    static void WritePdf(string path, IReadOnlyList<string> paragraphs)
    {
        using var document = SKDocument.CreatePdf(path);
        using var paint = new SKPaint { Color = SKColors.Black, IsAntialias = true, TextSize = 16, Typeface = SKTypeface.Default };
        var lines = paragraphs.SelectMany(paragraph => Wrap(paragraph, 70)).ToList();
        var cursor = 0;
        while (cursor < lines.Count)
        {
            using var canvas = document.BeginPage(595, 842);
            var y = 72f;
            while (cursor < lines.Count && y < 780)
            {
                canvas.DrawText(lines[cursor], 64, y, paint);
                y += 22;
                cursor++;
            }
            document.EndPage();
        }
        document.Close();
    }

    static IEnumerable<string> Wrap(string paragraph, int width)
    {
        var words = paragraph.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var line = "";
        foreach (var word in words)
        {
            if (line.Length + word.Length + 1 > width && line.Length > 0)
            {
                yield return line;
                line = word;
            }
            else line = line.Length == 0 ? word : line + " " + word;
        }
        if (line.Length > 0) yield return line;
    }

    static string EscapeRtf(string text) => text.Replace("\\", "\\\\").Replace("{", "\\{").Replace("}", "\\}");

    static void WriteEntry(ZipArchive zip, string name, string contents)
    {
        var entry = zip.CreateEntry(name);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
        writer.Write(contents);
    }
}
