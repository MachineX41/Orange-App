using System.IO.Compression;
using SkiaSharp;

namespace Orange.Engines.Tests;

public class EngineTests
{
    [Fact]
    public async Task ImageConvertsAndRotates()
    {
        var directory = Directory.CreateTempSubdirectory();
        OutputLocation.CustomDirectory = directory.FullName;
        try
        {
            var source = Path.Combine(directory.FullName, "pixel.png");
            using (var bitmap = new SKBitmap(16, 8))
            {
                using var canvas = new SKCanvas(bitmap);
                canvas.Clear(new SKColor(230, 80, 20));
                using var data = bitmap.Encode(SKEncodedImageFormat.Png, 100);
                using var stream = File.Create(source);
                data.SaveTo(stream);
            }
            var jpeg = await OrangeStudio.ConvertAsync(source, ConvertTarget.Jpeg);
            Assert.Equal("jpg", Path.GetExtension(jpeg[0]).TrimStart('.'));
            Assert.True(new FileInfo(jpeg[0]).Length > 0);
            var rotated = await OrangeStudio.RunAsync(ToolId.RotateImage, [source], new ToolRequest { QuartersClockwise = 1 });
            Assert.True(File.Exists(rotated[0]));
        }
        finally
        {
            OutputLocation.CustomDirectory = null;
        }
    }

    [Fact]
    public async Task ZipRoundTrip()
    {
        var directory = Directory.CreateTempSubdirectory();
        var note = Path.Combine(directory.FullName, "hello.txt");
        await File.WriteAllTextAsync(note, "orange");
        var zip = ArchiveStudio.Zip([note], directory.FullName);
        var extracted = await ArchiveStudio.Extract(zip, CancellationToken.None);
        Assert.Contains("hello.txt", Directory.GetFiles(extracted[0]).Select(Path.GetFileName));
    }

    [Fact]
    public async Task PowerPointBecomesPdf()
    {
        var directory = Directory.CreateTempSubdirectory();
        OutputLocation.CustomDirectory = directory.FullName;
        try
        {
            var deck = MakeDeck(directory.FullName);
            var pdf = await PresentationConverter.Convert(deck, CancellationToken.None);
            Assert.Equal("pdf", Path.GetExtension(pdf[0]).TrimStart('.'));
            Assert.Equal(2, PdfStudio.PageCount(pdf[0]));
            var text = PdfStudio.Text(pdf[0]);
            Assert.Contains("Orange slide", text);
            Assert.Contains("Grouped line", text);
            var outline = await PresentationConverter.Outline(deck, CancellationToken.None);
            Assert.Contains("Orange slide", outline);
            Assert.Contains("Grouped line", outline);
            var bytes = File.ReadAllBytes(pdf[0]);
            using var image = PDFtoImage.Conversion.ToImage(bytes, 0);
            var x = (int)(200.0 / 960 * (image.Width - 1));
            var y = (int)(150.0 / 540 * (image.Height - 1));
            var shape = image.GetPixel(x, y);
            Assert.True(shape.Red > 200, $"shape {shape}");
            Assert.True(shape.Blue < 80, $"shape {shape}");
        }
        finally
        {
            OutputLocation.CustomDirectory = null;
        }
    }

    [Fact]
    public async Task TextDocumentRoundTrip()
    {
        var directory = Directory.CreateTempSubdirectory();
        OutputLocation.CustomDirectory = directory.FullName;
        try
        {
            var note = Path.Combine(directory.FullName, "note.txt");
            await File.WriteAllTextAsync(note, "Orange keeps the original.");
            var pdf = await OrangeStudio.ConvertAsync(note, ConvertTarget.Pdf);
            Assert.Contains("Orange", PdfStudio.Text(pdf[0]));
        }
        finally
        {
            OutputLocation.CustomDirectory = null;
        }
    }

    static string MakeDeck(string directory)
    {
        var root = Path.Combine(directory, "deck");
        Directory.CreateDirectory(Path.Combine(root, "ppt/slides/_rels"));
        Directory.CreateDirectory(Path.Combine(root, "ppt/media"));
        Directory.CreateDirectory(Path.Combine(root, "ppt/theme"));
        Directory.CreateDirectory(Path.Combine(root, "ppt/_rels"));
        File.WriteAllText(Path.Combine(root, "ppt/presentation.xml"), """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <p:sldIdLst>
                <p:sldId id="256" r:id="rId1"/>
                <p:sldId id="257" r:id="rId2"/>
              </p:sldIdLst>
              <p:sldSz cx="12192000" cy="6858000"/>
            </p:presentation>
            """);
        File.WriteAllText(Path.Combine(root, "ppt/_rels/presentation.xml.rels"), """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
            </Relationships>
            """);
        File.WriteAllText(Path.Combine(root, "ppt/slides/slide1.xml"), """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <p:cSld><p:spTree>
                <p:sp><p:spPr>
                  <a:xfrm><a:off x="1270000" y="1270000"/><a:ext cx="2540000" cy="1270000"/></a:xfrm>
                  <a:prstGeom prst="rect"/>
                  <a:solidFill><a:srgbClr val="F26B1D"/></a:solidFill>
                </p:spPr></p:sp>
                <p:sp><p:spPr>
                  <a:xfrm><a:off x="1270000" y="3000000"/><a:ext cx="8000000" cy="1400000"/></a:xfrm>
                </p:spPr>
                <p:txBody><a:bodyPr/><a:p><a:r><a:rPr sz="3200" b="1"><a:solidFill><a:srgbClr val="112233"/></a:solidFill></a:rPr><a:t>Orange slide</a:t></a:r></a:p></p:txBody>
                </p:sp>
              </p:spTree></p:cSld>
            </p:sld>
            """);
        File.WriteAllText(Path.Combine(root, "ppt/slides/slide2.xml"), """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
              <p:cSld><p:spTree>
                <p:grpSp>
                  <p:grpSpPr><a:xfrm>
                    <a:off x="457200" y="457200"/><a:ext cx="8000000" cy="2000000"/>
                    <a:chOff x="0" y="0"/><a:chExt cx="8000000" cy="2000000"/>
                  </a:xfrm></p:grpSpPr>
                  <p:sp><p:spPr>
                    <a:xfrm><a:off x="0" y="0"/><a:ext cx="7000000" cy="1200000"/></a:xfrm>
                    <a:solidFill><a:schemeClr val="accent1"><a:lumMod val="80000"/></a:schemeClr></a:solidFill>
                  </p:spPr>
                  <p:txBody><a:bodyPr/><a:p><a:r><a:rPr sz="2400"/><a:t>Grouped line</a:t></a:r></a:p></p:txBody>
                  </p:sp>
                </p:grpSp>
              </p:spTree></p:cSld>
            </p:sld>
            """);
        File.WriteAllText(Path.Combine(root, "ppt/theme/theme1.xml"), """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
              <a:themeElements>
                <a:clrScheme name="Orange">
                  <a:dk1><a:srgbClr val="111111"/></a:dk1>
                  <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
                  <a:accent1><a:srgbClr val="F26B1D"/></a:accent1>
                </a:clrScheme>
              </a:themeElements>
            </a:theme>
            """);
        var deck = Path.Combine(directory, "deck.pptx");
        ZipFile.CreateFromDirectory(root, deck);
        return deck;
    }
}
