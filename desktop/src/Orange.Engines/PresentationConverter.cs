using System.IO.Compression;
using System.Xml.Linq;
using SkiaSharp;

namespace Orange;

/// <summary>
/// DrawingML slide painter. Order matches the macOS renderer: background, then shapes, pictures, groups, tables and charts.
/// </summary>
public static class PresentationConverter
{
    const double EmuPerPoint = 12700;

    public static Task<IReadOnlyList<string>> Convert(string path, CancellationToken cancellation)
    {
        var destination = UniqueDestination.Url(OutputLocation.DirectoryBeside(path), OutputLocation.BaseName(path), "pdf");
        using var package = Package.Open(path);
        using var document = SKDocument.CreatePdf(destination);
        foreach (var slide in package.Slides)
        {
            cancellation.ThrowIfCancellationRequested();
            using var canvas = document.BeginPage((float)package.Width, (float)package.Height);
            canvas.Clear(SKColors.White);
            var tree = slide.Tree.Descendants().FirstOrDefault(element => element.Name.LocalName == "spTree") ?? slide.Tree;
            DrawTree(canvas, tree, package, slide, new Space(0, 0, 1, 1));
            document.EndPage();
        }
        document.Close();
        return Task.FromResult<IReadOnlyList<string>>([destination]);
    }

    public static Task<string> Outline(string path, CancellationToken cancellation)
    {
        using var package = Package.Open(path);
        var lines = new List<string>();
        foreach (var slide in package.Slides)
        {
            foreach (var text in slide.Tree.Descendants().Where(element => element.Name.LocalName == "t"))
            {
                if (!string.IsNullOrWhiteSpace(text.Value)) lines.Add(text.Value.Trim());
            }
        }
        return Task.FromResult(string.Join("\n", lines));
    }

    static void DrawTree(SKCanvas canvas, XElement tree, Package package, Slide slide, Space space)
    {
        foreach (var child in tree.Elements())
        {
            switch (child.Name.LocalName)
            {
                case "sp":
                case "cxnSp":
                    DrawShape(canvas, child, package, slide, space);
                    break;
                case "pic":
                    DrawPicture(canvas, child, package, slide, space);
                    break;
                case "grpSp":
                    DrawGroup(canvas, child, package, slide, space);
                    break;
                case "graphicFrame":
                    DrawFrame(canvas, child, package, slide, space);
                    break;
            }
        }
    }

    static void DrawGroup(SKCanvas canvas, XElement group, Package package, Slide slide, Space space)
    {
        var transform = group.Element(group.Name.Namespace + "grpSpPr")?.Descendants().FirstOrDefault(element => element.Name.LocalName == "xfrm")
            ?? group.Descendants().FirstOrDefault(element => element.Name.LocalName == "xfrm");
        var childSpace = space;
        if (transform is not null)
        {
            var off = Box(transform, "off");
            var ext = Box(transform, "ext");
            var chOff = Box(transform, "chOff");
            var chExt = Box(transform, "chExt");
            childSpace = new Space(off.X, off.Y, ext.Width / Math.Max(1, chExt.Width), ext.Height / Math.Max(1, chExt.Height), chOff.X, chOff.Y);
        }
        var tree = group.Elements().FirstOrDefault(element => element.Name.LocalName == "spTree") ?? group;
        DrawTree(canvas, tree, package, slide, childSpace);
    }

    static void DrawShape(SKCanvas canvas, XElement shape, Package package, Slide slide, Space space)
    {
        var properties = shape.Descendants().FirstOrDefault(element => element.Name.LocalName == "spPr");
        var box = Frame(properties, space);
        var geometry = properties?.Descendants().FirstOrDefault(element => element.Name.LocalName == "prstGeom");
        var preset = geometry?.Attribute("prst")?.Value ?? "rect";
        using var path = ShapeGeometry.Build(preset, new PresentationBounds(box.X, box.Y, box.Width, box.Height));
        var fill = ColorOf(properties, package.Theme);
        if (fill is { } color)
        {
            using var paint = new SKPaint { Color = color, Style = SKPaintStyle.Fill, IsAntialias = true };
            canvas.DrawPath(path, paint);
        }
        var line = properties?.Descendants().FirstOrDefault(element => element.Name.LocalName == "ln");
        var stroke = ColorOf(line, package.Theme);
        if (stroke is { } lineColor)
        {
            using var paint = new SKPaint { Color = lineColor, Style = SKPaintStyle.Stroke, StrokeWidth = 1.5f, IsAntialias = true };
            canvas.DrawPath(path, paint);
        }
        var body = shape.Descendants().FirstOrDefault(element => element.Name.LocalName == "txBody");
        if (body is not null) DrawText(canvas, body, box, package);
    }

    static void DrawPicture(SKCanvas canvas, XElement picture, Package package, Slide slide, Space space)
    {
        var properties = picture.Descendants().FirstOrDefault(element => element.Name.LocalName == "spPr");
        var box = Frame(properties, space);
        var embed = picture.Descendants().FirstOrDefault(element => element.Name.LocalName == "blip")?.Attribute(XName.Get("embed", "http://schemas.openxmlformats.org/officeDocument/2006/relationships"))?.Value;
        if (embed is null || !slide.Rels.TryGetValue(embed, out var target)) return;
        var bytes = package.Bytes(slide.Directory, target);
        if (bytes is null) return;
        var ext = Path.GetExtension(target).ToLowerInvariant();
        if (ext is ".emf" or ".wmf")
        {
            MetafileDrawer.Draw(canvas, bytes, new PresentationBounds(box.X, box.Y, box.Width, box.Height));
            return;
        }
        using var bitmap = SKBitmap.Decode(bytes);
        if (bitmap is null) return;
        canvas.DrawBitmap(bitmap, new SKRect((float)box.X, (float)box.Y, (float)box.Right, (float)box.Bottom));
    }

    static void DrawFrame(SKCanvas canvas, XElement frame, Package package, Slide slide, Space space)
    {
        var box = Frame(frame.Descendants().FirstOrDefault(element => element.Name.LocalName == "xfrm")?.Parent, space);
        var table = frame.Descendants().FirstOrDefault(element => element.Name.LocalName == "tbl");
        if (table is not null)
        {
            DrawTable(canvas, table, box, package);
            return;
        }
        var chartId = frame.Descendants().FirstOrDefault(element => element.Name.LocalName == "chart")
            ?.Attribute(XName.Get("id", "http://schemas.openxmlformats.org/officeDocument/2006/relationships"))?.Value;
        if (chartId is not null && slide.Rels.TryGetValue(chartId, out var chartPath))
        {
            var bytes = package.Bytes(slide.Directory, chartPath);
            if (bytes is not null) ChartRenderer.Draw(canvas, bytes, new PresentationBounds(box.X, box.Y, box.Width, box.Height), package.Theme);
        }
    }

    static void DrawTable(SKCanvas canvas, XElement table, Bounds box, Package package)
    {
        var rows = table.Elements().Where(element => element.Name.LocalName == "tr").ToList();
        if (rows.Count == 0) return;
        var rowHeight = box.Height / rows.Count;
        for (var rowIndex = 0; rowIndex < rows.Count; rowIndex++)
        {
            var cells = rows[rowIndex].Elements().Where(element => element.Name.LocalName == "tc").ToList();
            if (cells.Count == 0) continue;
            var cellWidth = box.Width / cells.Count;
            for (var column = 0; column < cells.Count; column++)
            {
                var cell = new Bounds(box.X + column * cellWidth, box.Y + rowIndex * rowHeight, cellWidth, rowHeight);
                using var paint = new SKPaint { Color = new SKColor(242, 107, 29, 30), Style = SKPaintStyle.Fill };
                canvas.DrawRect(cell.Rect, paint);
                using var stroke = new SKPaint { Color = new SKColor(30, 30, 30), Style = SKPaintStyle.Stroke, StrokeWidth = 0.6f };
                canvas.DrawRect(cell.Rect, stroke);
                var body = cells[column].Descendants().FirstOrDefault(element => element.Name.LocalName == "txBody");
                if (body is not null) DrawText(canvas, body, cell, package);
            }
        }
    }

    static void DrawText(SKCanvas canvas, XElement body, Bounds box, Package package)
    {
        var y = (float)box.Y + 8;
        foreach (var paragraph in body.Elements().Where(element => element.Name.LocalName == "p"))
        {
            var runs = paragraph.Descendants().Where(element => element.Name.LocalName == "r").ToList();
            if (runs.Count == 0)
            {
                var plain = string.Concat(paragraph.Descendants().Where(element => element.Name.LocalName == "t").Select(element => element.Value));
                if (plain.Length > 0) y = DrawRun(canvas, plain, 18, false, new SKColor(17, 34, 51), box, y);
                continue;
            }
            foreach (var run in runs)
            {
                var text = string.Concat(run.Elements().Where(element => element.Name.LocalName == "t").Select(element => element.Value));
                if (text.Length == 0) continue;
                var props = run.Elements().FirstOrDefault(element => element.Name.LocalName == "rPr");
                var size = 18.0;
                if (double.TryParse(props?.Attribute("sz")?.Value, out var hundredths)) size = hundredths / 100;
                var bold = props?.Attribute("b")?.Value == "1";
                var color = ColorOf(props, package.Theme) ?? new SKColor(17, 34, 51);
                y = DrawRun(canvas, text, (float)size, bold, color, box, y);
            }
        }
    }

    static float DrawRun(SKCanvas canvas, string text, float size, bool bold, SKColor color, Bounds box, float y)
    {
        using var typeface = SlideFonts.Body(bold);
        using var paint = new SKPaint
        {
            Color = color,
            TextSize = size,
            Typeface = typeface,
            IsAntialias = true
        };
        canvas.DrawText(text, (float)box.X + 8, y + size, paint);
        return y + size * 1.3f;
    }

    static SKColor? ColorOf(XElement? parent, Theme theme)
    {
        if (parent is null) return null;
        var solid = parent.Descendants().FirstOrDefault(element => element.Name.LocalName is "srgbClr" or "schemeClr");
        if (solid is null) return null;
        SKColor color;
        if (solid.Name.LocalName == "srgbClr")
        {
            color = Hex(solid.Attribute("val")?.Value);
        }
        else
        {
            color = theme.Scheme(solid.Attribute("val")?.Value);
        }
        var lum = solid.Elements().FirstOrDefault(element => element.Name.LocalName == "lumMod");
        if (lum is not null && double.TryParse(lum.Attribute("val")?.Value, out var mod))
        {
            var scale = mod / 100_000;
            color = new SKColor((byte)(color.Red * scale), (byte)(color.Green * scale), (byte)(color.Blue * scale), color.Alpha);
        }
        return color;
    }

    static SKColor Hex(string? value)
    {
        if (string.IsNullOrEmpty(value) || value.Length < 6) return new SKColor(242, 107, 29);
        var number = System.Convert.ToUInt32(value[..6], 16);
        return new SKColor((byte)(number >> 16), (byte)(number >> 8), (byte)number);
    }

    static Bounds Frame(XElement? properties, Space space)
    {
        var transform = properties?.Descendants().FirstOrDefault(element => element.Name.LocalName == "xfrm")
            ?? properties;
        var off = Box(transform, "off");
        var ext = Box(transform, "ext");
        return space.Map(off.X, off.Y, ext.Width, ext.Height);
    }

    static Bounds Box(XElement? transform, string name)
    {
        var node = transform?.Elements().FirstOrDefault(element => element.Name.LocalName == name);
        double.TryParse(node?.Attribute("x")?.Value ?? node?.Attribute("cx")?.Value, out var x);
        double.TryParse(node?.Attribute("y")?.Value ?? node?.Attribute("cy")?.Value, out var y);
        if (name == "ext" || name == "chExt")
        {
            double.TryParse(node?.Attribute("cx")?.Value, out x);
            double.TryParse(node?.Attribute("cy")?.Value, out y);
            return new Bounds(0, 0, x / EmuPerPoint, y / EmuPerPoint);
        }
        return new Bounds(x / EmuPerPoint, y / EmuPerPoint, 0, 0);
    }

    readonly record struct Bounds(double X, double Y, double Width, double Height)
    {
        public double Right => X + Width;
        public double Bottom => Y + Height;
        public SKRect Rect => new((float)X, (float)Y, (float)Right, (float)Bottom);
    }

    readonly record struct Space(double OriginX, double OriginY, double ScaleX, double ScaleY, double ChildX = 0, double ChildY = 0)
    {
        public Bounds Map(double x, double y, double width, double height) => new(
            OriginX + (x - ChildX) * ScaleX,
            OriginY + (y - ChildY) * ScaleY,
            width * ScaleX,
            height * ScaleY);
    }

    sealed class Package : IDisposable
    {
        readonly ZipArchive zip;
        public double Width { get; }
        public double Height { get; }
        public Theme Theme { get; }
        public IReadOnlyList<Slide> Slides { get; }

        Package(ZipArchive zip, double width, double height, Theme theme, IReadOnlyList<Slide> slides)
        {
            this.zip = zip;
            Width = width;
            Height = height;
            Theme = theme;
            Slides = slides;
        }

        public static Package Open(string path)
        {
            ZipArchive zip;
            try { zip = ZipFile.OpenRead(path); }
            catch { throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path)); }
            var presentation = ReadXml(zip, "ppt/presentation.xml") ?? throw new OrangeException(OrangeErrorCode.Unreadable, Path.GetFileName(path));
            var size = presentation.Descendants().FirstOrDefault(element => element.Name.LocalName == "sldSz");
            var width = Attribute(size, "cx", 12192000) / EmuPerPoint;
            var height = Attribute(size, "cy", 6858000) / EmuPerPoint;
            var rels = Relationships(zip, "ppt/_rels/presentation.xml.rels");
            var themeEntry = rels.Values.FirstOrDefault(value => value.Contains("theme", StringComparison.OrdinalIgnoreCase)) ?? "theme/theme1.xml";
            var themeXml = ReadXml(zip, "ppt/" + themeEntry.TrimStart('/'));
            var slides = new List<Slide>();
            foreach (var pair in rels.Where(pair => pair.Value.Contains("slide", StringComparison.OrdinalIgnoreCase) && !pair.Value.Contains("slideLayout", StringComparison.OrdinalIgnoreCase) && !pair.Value.Contains("slideMaster", StringComparison.OrdinalIgnoreCase)))
            {
                var slidePath = "ppt/" + pair.Value.Replace("\\", "/");
                var tree = ReadXml(zip, slidePath);
                if (tree is null) continue;
                var directory = Path.GetDirectoryName(slidePath)?.Replace("\\", "/") ?? "ppt/slides";
                var slideRels = Relationships(zip, directory + "/_rels/" + Path.GetFileName(slidePath) + ".rels");
                slides.Add(new Slide(tree, directory, slideRels));
            }
            return new Package(zip, width, height, Theme.Read(themeXml), slides);
        }

        public byte[]? Bytes(string directory, string relative)
        {
            var combined = Path.GetFullPath(Path.Combine(directory, relative)).Replace("\\", "/");
            var marker = combined.IndexOf("/ppt/", StringComparison.Ordinal);
            var name = marker >= 0 ? combined[(marker + 1)..] : "ppt/" + relative;
            var entry = zip.GetEntry(name) ?? zip.Entries.FirstOrDefault(item => item.FullName.Replace("\\", "/").EndsWith(relative.Replace("\\", "/"), StringComparison.OrdinalIgnoreCase));
            if (entry is null || entry.FullName.Contains("..", StringComparison.Ordinal)) return null;
            using var stream = entry.Open();
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            return memory.ToArray();
        }

        public void Dispose() => zip.Dispose();

        static double Attribute(XElement? element, string name, double fallback) =>
            double.TryParse(element?.Attribute(name)?.Value, out var value) ? value : fallback;

        static XElement? ReadXml(ZipArchive zip, string name)
        {
            var entry = zip.GetEntry(name) ?? zip.Entries.FirstOrDefault(item => item.FullName.Replace("\\", "/") == name);
            if (entry is null) return null;
            using var stream = entry.Open();
            return XDocument.Load(stream).Root;
        }

        static Dictionary<string, string> Relationships(ZipArchive zip, string name)
        {
            var xml = ReadXml(zip, name);
            var map = new Dictionary<string, string>();
            if (xml is null) return map;
            foreach (var rel in xml.Elements())
            {
                var id = rel.Attribute("Id")?.Value;
                var target = rel.Attribute("Target")?.Value;
                if (id is not null && target is not null) map[id] = target;
            }
            return map;
        }
    }

    sealed record Slide(XElement Tree, string Directory, Dictionary<string, string> Rels);

    public sealed class Theme
    {
        readonly Dictionary<string, SKColor> colors;
        Theme(Dictionary<string, SKColor> colors) => this.colors = colors;
        public static Theme Read(XElement? theme)
        {
            var colors = new Dictionary<string, SKColor>(StringComparer.OrdinalIgnoreCase)
            {
                ["dk1"] = SKColors.Black,
                ["lt1"] = SKColors.White,
                ["accent1"] = new SKColor(242, 107, 29)
            };
            if (theme is null) return new Theme(colors);
            foreach (var element in theme.Descendants().Where(element => element.Elements().Any(child => child.Name.LocalName is "srgbClr" or "sysClr")))
            {
                var rgb = element.Descendants().FirstOrDefault(child => child.Name.LocalName == "srgbClr")?.Attribute("val")?.Value;
                if (rgb is not null) colors[element.Name.LocalName] = Hex(rgb);
            }
            return new Theme(colors);
        }

        public SKColor Scheme(string? name) => name is not null && colors.TryGetValue(name, out var color) ? color : colors["accent1"];
    }
}

public static class SlideFonts
{
    public static SKTypeface Body(bool bold)
    {
        foreach (var path in Candidates())
        {
            var face = SKTypeface.FromFile(path);
            if (face is not null) return face;
        }
        return SKTypeface.FromFamilyName(bold ? "Helvetica" : "Helvetica", bold ? SKFontStyle.Bold : SKFontStyle.Normal)
            ?? SKTypeface.Default;
    }

    static IEnumerable<string> Candidates()
    {
        yield return "/System/Library/Fonts/Supplemental/Arial.ttf";
        yield return "/System/Library/Fonts/Helvetica.ttc";
        yield return "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
        yield return "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf";
        yield return "C:\\Windows\\Fonts\\arial.ttf";
    }
}

public static class ShapeGeometry
{
    public static SKPath Build(string preset, PresentationBounds box)
    {
        var path = new SKPath();
        var rect = new SKRect((float)box.X, (float)box.Y, (float)box.Right, (float)box.Bottom);
        switch (preset)
        {
            case "ellipse":
            case "flowChartConnector":
                path.AddOval(rect);
                break;
            case "roundRect":
                path.AddRoundRect(rect, rect.Width * 0.1f, rect.Height * 0.1f);
                break;
            case "triangle":
            case "isoscelesTriangle":
                path.MoveTo(rect.MidX, rect.Top);
                path.LineTo(rect.Right, rect.Bottom);
                path.LineTo(rect.Left, rect.Bottom);
                path.Close();
                break;
            case "diamond":
                path.MoveTo(rect.MidX, rect.Top);
                path.LineTo(rect.Right, rect.MidY);
                path.LineTo(rect.MidX, rect.Bottom);
                path.LineTo(rect.Left, rect.MidY);
                path.Close();
                break;
            case "heart":
                path.MoveTo(rect.MidX, rect.Bottom);
                path.CubicTo(rect.Left, rect.MidY, rect.Left, rect.Top, rect.MidX, rect.Top + rect.Height * 0.3f);
                path.CubicTo(rect.Right, rect.Top, rect.Right, rect.MidY, rect.MidX, rect.Bottom);
                path.Close();
                break;
            case "line":
            case "straightConnector1":
                path.MoveTo(rect.Left, rect.Top);
                path.LineTo(rect.Right, rect.Bottom);
                break;
            default:
                path.AddRect(rect);
                break;
        }
        return path;
    }
}

public readonly record struct PresentationBounds(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

public static class ChartRenderer
{
    public static void Draw(SKCanvas canvas, byte[] chartXml, PresentationBounds box, PresentationConverter.Theme theme)
    {
        var xml = XDocument.Parse(System.Text.Encoding.UTF8.GetString(chartXml)).Root;
        if (xml is null) return;
        var values = xml.Descendants().Where(element => element.Name.LocalName is "numCache" or "numLit")
            .SelectMany(cache => cache.Descendants().Where(point => point.Name.LocalName == "pt"))
            .Select(point => double.TryParse(point.Descendants().FirstOrDefault(value => value.Name.LocalName == "v")?.Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var number) ? number : 0)
            .ToList();
        if (values.Count == 0) return;
        var max = Math.Max(1, values.Max());
        var slot = box.Width / values.Count;
        using var paint = new SKPaint { Color = theme.Scheme("accent1"), Style = SKPaintStyle.Fill, IsAntialias = true };
        for (var index = 0; index < values.Count; index++)
        {
            var height = box.Height * (values[index] / max);
            canvas.DrawRect(new SKRect(
                (float)(box.X + index * slot + slot * 0.15),
                (float)(box.Bottom - height),
                (float)(box.X + (index + 1) * slot - slot * 0.15),
                (float)box.Bottom), paint);
        }
    }
}

public static class MetafileDrawer
{
    public static void Draw(SKCanvas canvas, byte[] data, PresentationBounds box)
    {
        if (data.Length < 8) return;
        using var paint = new SKPaint { Color = new SKColor(40, 40, 40), Style = SKPaintStyle.Stroke, StrokeWidth = 1.2f, IsAntialias = true };
        using var fill = new SKPaint { Color = new SKColor(242, 107, 29, 180), Style = SKPaintStyle.Fill, IsAntialias = true };
        canvas.Save();
        canvas.ClipRect(new SKRect((float)box.X, (float)box.Y, (float)box.Right, (float)box.Bottom));
        var cursor = 0;
        var x = (float)box.X;
        var y = (float)box.Y;
        if (data.Length > 40 && data[40] == 0x20 && data[41] == 0x45 && data[42] == 0x4D && data[43] == 0x46)
        {
            cursor = 8;
        }
        while (cursor + 8 <= data.Length)
        {
            var type = BitConverter.ToUInt32(data, cursor);
            var size = BitConverter.ToInt32(data, cursor + 4);
            if (size < 8 || cursor + size > data.Length) break;
            switch (type)
            {
                case 27:
                    x = (float)box.X + ReadI32(data, cursor + 8);
                    y = (float)box.Y + ReadI32(data, cursor + 12);
                    break;
                case 42:
                    canvas.DrawOval(ReadRect(data, cursor + 8, box), fill);
                    break;
                case 43:
                    canvas.DrawRect(ReadRect(data, cursor + 8, box), fill);
                    canvas.DrawRect(ReadRect(data, cursor + 8, box), paint);
                    break;
                case 54:
                    var nextX = (float)box.X + ReadI32(data, cursor + 8);
                    var nextY = (float)box.Y + ReadI32(data, cursor + 12);
                    canvas.DrawLine(x, y, nextX, nextY, paint);
                    x = nextX;
                    y = nextY;
                    break;
            }
            cursor += size;
        }
        canvas.Restore();
    }

    static int ReadI32(byte[] data, int offset) => offset + 4 <= data.Length ? BitConverter.ToInt32(data, offset) : 0;

    static SKRect ReadRect(byte[] data, int offset, PresentationBounds box)
    {
        var left = ReadI32(data, offset);
        var top = ReadI32(data, offset + 4);
        var right = ReadI32(data, offset + 8);
        var bottom = ReadI32(data, offset + 12);
        return new SKRect((float)box.X + left, (float)box.Y + top, (float)box.X + right, (float)box.Y + bottom);
    }
}
