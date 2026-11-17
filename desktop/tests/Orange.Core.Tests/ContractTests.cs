using Orange;

namespace Orange.Core.Tests;

public class CatalogTests
{
    [Fact]
    public void KindDetection()
    {
        Assert.Equal(MediaKind.Image, Catalog.Kind("/tmp/a.JPG"));
        Assert.Equal(MediaKind.Video, Catalog.Kind("/tmp/a.mp4"));
        Assert.Equal(MediaKind.Audio, Catalog.Kind("/tmp/a.mp3"));
        Assert.Equal(MediaKind.Pdf, Catalog.Kind("/tmp/a.pdf"));
        Assert.Equal(MediaKind.Archive, Catalog.Kind("/tmp/a.zip"));
        Assert.Equal(MediaKind.Document, Catalog.Kind("/tmp/a.docx"));
        Assert.Equal(MediaKind.Document, Catalog.Kind("/tmp/a.pptx"));
        Assert.Equal([ConvertTarget.Pdf, ConvertTarget.Txt], Catalog.ConvertTargetsFor("/tmp/a.pptx"));
    }

    [Fact]
    public void TargetsExcludeOwnFormat()
    {
        var targets = Catalog.ConvertTargetsFor("/tmp/a.jpeg");
        Assert.DoesNotContain(ConvertTarget.Jpeg, targets);
        Assert.Contains(ConvertTarget.Png, targets);
        Assert.Contains(ConvertTarget.Pdf, targets);
    }

    [Fact]
    public void MixedSelectionHasNoSharedTarget()
    {
        Assert.Empty(Catalog.CommonConvertTargets(["/tmp/a.png", "/tmp/b.mp4"]));
    }

    [Fact]
    public void MultiFileToolsRequireBatchSupport()
    {
        var one = Catalog.CommonTools(["/tmp/a.pdf"]);
        Assert.DoesNotContain(ToolId.MergePdf, one);
        Assert.Contains(ToolId.SplitPdf, one);
        var two = Catalog.CommonTools(["/tmp/a.pdf", "/tmp/b.pdf"]);
        Assert.Contains(ToolId.MergePdf, two);
        Assert.DoesNotContain(ToolId.SplitPdf, two);
    }
}

public class WheelLayoutTests
{
    readonly WheelLayout layout = new(new Point(200, 200), 100, 40, 160, 4);

    [Fact]
    public void CardinalIndexes()
    {
        Assert.Equal(0, layout.IndexAt(new Point(200, 100)));
        Assert.Equal(1, layout.IndexAt(new Point(300, 200)));
        Assert.Equal(2, layout.IndexAt(new Point(200, 300)));
        Assert.Equal(3, layout.IndexAt(new Point(100, 200)));
        Assert.Equal(0, layout.IndexAt(new Point(190, 95)));
        Assert.Null(layout.IndexAt(new Point(200, 200)));
        Assert.Null(layout.IndexAt(new Point(200, 10)));
    }

    [Fact]
    public void PointForTopItem()
    {
        var point = layout.PointFor(0);
        Assert.Equal(200, point.X, 3);
        Assert.Equal(100, point.Y, 3);
    }
}

public class CropMathTests
{
    [Fact]
    public void AspectFitCentersShortImage()
    {
        var fitted = CropMath.FittedRect(new Size(200, 100), new Size(200, 200));
        Assert.Equal(new Rect(0, 50, 200, 100), fitted);
    }

    [Fact]
    public void TopHalfMapsToUpperPixels()
    {
        var pixels = CropMath.PixelRect(new Rect(0, 0, 1, 0.5), new Size(200, 100));
        Assert.Equal(new Rect(0, 50, 200, 50), pixels);
    }
}

public class PageSelectionTests
{
    [Fact]
    public void ParsesCommaRanges()
    {
        Assert.Equal([(1, 2), (4, 4)], PageSelection.Parse("1-2, 4", 6));
    }

    [Fact]
    public void AllKeyword()
    {
        Assert.Equal([(1, 3)], PageSelection.Parse("hepsi", 3));
    }

    [Fact]
    public void RejectsReversedRange()
    {
        Assert.Throws<OrangeException>(() => PageSelection.Parse("4-2", 6));
    }
}

public class DestinationTests
{
    [Fact]
    public void AvoidsExistingName()
    {
        var directory = Directory.CreateTempSubdirectory();
        File.WriteAllText(Path.Combine(directory.FullName, "Note.txt"), "a");
        var next = UniqueDestination.Url(directory.FullName, "Note", "txt");
        Assert.Equal(Path.Combine(directory.FullName, "Note 2.txt"), next);
    }
}

public class LanguageTests
{
    [Fact]
    public void ChoiceOverridesTheSystemLanguage()
    {
        var previous = Lang.Choice;
        Lang.Choice = LanguageChoice.Turkish;
        Assert.Equal("Kaydet", Lang.T("Save", "Kaydet"));
        Lang.Choice = LanguageChoice.English;
        Assert.Equal("Save", Lang.T("Save", "Kaydet"));
        Lang.Choice = previous;
    }

    [Fact]
    public void SystemLanguageFallsBackToEnglish()
    {
        Assert.True(Lang.SystemPrefersTurkish(["tr-TR"]));
        Assert.True(Lang.SystemPrefersTurkish(["de", "tr"]));
        Assert.False(Lang.SystemPrefersTurkish(["en-GB"]));
        Assert.False(Lang.SystemPrefersTurkish(["en", "tr"]));
        Assert.False(Lang.SystemPrefersTurkish(["de", "fr"]));
        Assert.False(Lang.SystemPrefersTurkish([]));
    }
}

public class CodeActionTests
{
    [Fact]
    public void WebLinks()
    {
        Assert.Equal("apple.com", CodeAction.Parse("https://www.apple.com/tr/").Destination);
        Assert.IsType<CodeAction.WebAction>(CodeAction.Parse("www.example.com/menu"));
        Assert.IsType<CodeAction.WebAction>(CodeAction.Parse("example.org"));
        Assert.True(CodeAction.Parse("http://example.com").IsInsecure);
        Assert.False(CodeAction.Parse("https://example.com").IsInsecure);
    }

    [Fact]
    public void ContactSchemes()
    {
        Assert.Equal("ali@example.com", CodeAction.Parse("mailto:ali@example.com").Destination);
        Assert.IsType<CodeAction.EmailAction>(CodeAction.Parse("ali@example.com"));
        Assert.Equal("+905551112233", CodeAction.Parse("tel:+905551112233").Destination);
        var sms = Assert.IsType<CodeAction.MessageAction>(CodeAction.Parse("SMSTO:+905551112233:Merhaba"));
        Assert.Equal("sms", sms.Address.Scheme);
        var mail = Assert.IsType<CodeAction.EmailAction>(CodeAction.Parse("MATMSG:TO:ali@example.com;SUB:Selam;BODY:Nasılsın;;"));
        Assert.StartsWith("mailto:ali@example.com", mail.Address.AbsoluteUri);
        var map = Assert.IsType<CodeAction.MapAction>(CodeAction.Parse("geo:41.0082,28.9784"));
        Assert.Equal("maps.apple.com", map.Address.Host);
    }

    [Fact]
    public void Wifi()
    {
        Assert.Equal(new CodeAction.WifiAction("Ev Ağı", "gizli;123"), CodeAction.Parse("WIFI:T:WPA;S:Ev Ağı;P:gizli\\;123;;"));
        Assert.Equal(new CodeAction.WifiAction("Kafe", null), CodeAction.Parse("WIFI:T:nopass;S:Kafe;;"));
    }

    [Fact]
    public void UnsafeOrPlainPayloadsStayText()
    {
        Assert.IsType<CodeAction.TextAction>(CodeAction.Parse("javascript:alert(1)"));
        Assert.IsType<CodeAction.TextAction>(CodeAction.Parse("file:///etc/passwd"));
        Assert.IsType<CodeAction.TextAction>(CodeAction.Parse("4006381333931"));
        Assert.IsType<CodeAction.TextAction>(CodeAction.Parse("Merhaba dünya"));
        Assert.IsType<CodeAction.TextAction>(CodeAction.Parse("https://localhost"));
        Assert.IsType<CodeAction.TextAction>(CodeAction.Parse("v1.2"));
    }
}

public class ProgressTests
{
    [Fact]
    public void ProgressFollowsTheNewestPercent()
    {
        var reader = new DownloadProgressReader();
        var first = reader.Feed("ORANGEPROG:0.0\rORANGEPROG:12.5\r");
        Assert.Equal(2, first.Count);
        Assert.Equal(0, first[0], 4);
        Assert.Equal(0.125, first[1], 4);
        var split = reader.Feed("ORANGEPROG:40").Concat(reader.Feed(".5\n[download]  80.0% of 1.00MiB\n")).ToArray();
        Assert.Equal(2, split.Length);
        Assert.Equal(0.405, split[0], 3);
        Assert.Equal(0.8, split[1], 3);
    }

    [Fact]
    public void ColoredAndUnknownPercents()
    {
        var reader = new DownloadProgressReader();
        var updates = reader.Feed("\u001B[0;94m[download]\u001B[0m   7.5% of 2.00MiB\n[download]  N/A% of Unknown\n");
        Assert.Single(updates);
        Assert.Equal(0.075, updates[0], 4);
        var finished = reader.Finish();
        Assert.Null(finished.Progress);
        Assert.Empty(finished.Paths);
    }
}

public class LinkTests
{
    [Fact]
    public void MediaLinkDiscovery()
    {
        var html = """<html><head><meta property="og:video" content="/clip.mp4?a=1&amp;b=2"></head></html>""";
        var link = LinkDiscovery.MediaLink(html, new Uri("https://example.com/page"));
        Assert.Equal("https://example.com/clip.mp4?a=1&b=2", link?.AbsoluteUri);
    }
}

public class BitrateTests
{
    [Fact]
    public void CompactTargets()
    {
        Assert.Equal(7_464_960, VideoBitrate.Compact(1920 * 1080, 30, 20_000_000, true));
        var efficient = VideoBitrate.Compact(1920 * 1080, 30, 4_000_000, true);
        Assert.Equal(3_200_000, efficient);
        Assert.True(efficient < 4_000_000);
    }
}

public class AudioMathTests
{
    [Fact]
    public void SilenceNormalizeAndBleep()
    {
        var rate = 44100.0;
        var tone = Enumerable.Range(0, (int)(rate * 2)).Select(index => index < rate * 0.3 ? 0 : 0.4f * MathF.Sin(2 * MathF.PI * 440 * index / (float)rate)).ToArray();
        var clip = new AudioBuffer(rate, [tone, tone]);
        Assert.Equal(2, clip.Duration, 2);
        Assert.Equal(0.3, clip.SilenceBounds().Start, 2);
        Assert.Equal(1, clip.Remixed(true, [1]).ChannelCount);
        Assert.Equal(-1, AudioBuffer.Decibels(clip.NormalizedPeak(-1).Peak), 1);
        var bleeped = clip.Bleeped((0.5, 1.0), false);
        Assert.True(bleeped.Trimmed(0.6, 0.9).Peak < 0.001f);
    }
}

public class WheelKeyTests
{
    [Fact]
    public void ModifiersMapToModes()
    {
        Assert.Equal(WheelMode.Convert, WheelKeys.Mode(true, true, true));
        Assert.Equal(WheelMode.Tools, WheelKeys.Mode(false, true, true));
        Assert.Equal(WheelMode.Actions, WheelKeys.Mode(false, false, true));
        Assert.Null(WheelKeys.Mode(false, false, false));
    }
}
