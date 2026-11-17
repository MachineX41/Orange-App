using System.Diagnostics;
using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;

namespace Orange.App;

public class EditorWindow : Window
{
    readonly ToolId tool;
    readonly string[] paths;
    readonly ToolRequest request = new();
    readonly TextBlock status = new() { TextWrapping = Avalonia.Media.TextWrapping.Wrap };
    readonly List<Slider> adjustments = [];
    TextBox? startBox;
    TextBox? endBox;
    Slider? playhead;
    Process? preview;

    public EditorWindow(ToolId tool, IReadOnlyList<string> paths)
    {
        this.tool = tool;
        this.paths = paths.ToArray();
        Title = MainWindow.ToolTitle(tool);
        Width = 520;
        Height = 460;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var stack = new StackPanel { Margin = new Thickness(20), Spacing = 10 };
        stack.Children.Add(new TextBlock { Text = string.Join("\n", this.paths.Select(Path.GetFileName)), Opacity = 0.7 });
        AddFields(stack);
        var apply = new Button { Content = Lang.T("Apply", "Uygula"), HorizontalAlignment = HorizontalAlignment.Right };
        apply.Click += async (_, _) => await Apply();
        stack.Children.Add(apply);
        stack.Children.Add(status);
        Content = new ScrollViewer { Content = stack };
        KeyDown += (_, eventArgs) => HandleKey(eventArgs);
    }

    void HandleKey(KeyEventArgs eventArgs)
    {
        var typing = TopLevel.GetTopLevel(this)?.FocusManager?.GetFocusedElement() is TextBox;
        if (eventArgs.Key == Key.Escape) { Close(); eventArgs.Handled = true; return; }
        if (eventArgs.Key == Key.Enter && !typing) { _ = Apply(); eventArgs.Handled = true; return; }
        if (typing) return;
        switch (eventArgs.Key)
        {
            case Key.Space:
                TogglePreview();
                eventArgs.Handled = true;
                break;
            case Key.I:
                SetTime(startBox, Playhead());
                eventArgs.Handled = true;
                break;
            case Key.O:
                SetTime(endBox, Playhead());
                eventArgs.Handled = true;
                break;
            case Key.S when tool == ToolId.SplitVideo:
                SetTime(startBox, Playhead());
                eventArgs.Handled = true;
                break;
            case Key.M when tool == ToolId.AdjustImage:
                foreach (var slider in adjustments) slider.Value = 0;
                eventArgs.Handled = true;
                break;
        }
    }

    double Playhead() => playhead?.Value ?? request.Start;

    static void SetTime(TextBox? box, double seconds)
    {
        if (box is null) return;
        box.Text = seconds.ToString("0.###", CultureInfo.InvariantCulture);
    }

    void TogglePreview()
    {
        if (preview is { HasExited: false })
        {
            preview.Kill(entireProcessTree: true);
            preview = null;
            status.Text = Lang.T("Paused", "Durdu");
            return;
        }
        var player = Ffmpeg.Locate("ffplay");
        if (player is null)
        {
            status.Text = Lang.T("ffplay is required to preview.", "Önizleme için ffplay gerekli.");
            return;
        }
        var start = request.Start.ToString(CultureInfo.InvariantCulture);
        var length = Math.Max(0.2, (request.End > request.Start ? request.End : request.Start + 5) - request.Start).ToString(CultureInfo.InvariantCulture);
        var info = new ProcessStartInfo(player) { UseShellExecute = false, CreateNoWindow = true };
        info.ArgumentList.Add("-ss");
        info.ArgumentList.Add(start);
        info.ArgumentList.Add("-t");
        info.ArgumentList.Add(length);
        info.ArgumentList.Add("-autoexit");
        info.ArgumentList.Add(paths[0]);
        preview = Process.Start(info);
    }

    void AddFields(StackPanel stack)
    {
        switch (tool)
        {
            case ToolId.AdjustImage:
                AddSlider(stack, Lang.T("Brightness", "Parlaklık"), -1, 1, value => request.Adjust.Brightness = value);
                AddSlider(stack, Lang.T("Contrast", "Kontrast"), -1, 1, value => request.Adjust.Contrast = value);
                AddSlider(stack, Lang.T("Saturation", "Doygunluk"), -1, 1, value => request.Adjust.Saturation = value);
                AddSlider(stack, Lang.T("Warmth", "Sıcaklık"), -1, 1, value => request.Adjust.Warmth = value);
                AddSlider(stack, Lang.T("Sharpness", "Keskinlik"), 0, 1, value => request.Adjust.Sharpness = value);
                break;
            case ToolId.CropImage:
            case ToolId.CropVideo:
                Box(stack, "x,y,w,h", "0,0,1,1", text =>
                {
                    var parts = text.Split(',').Select(double.Parse).ToArray();
                    if (parts.Length == 4) request.Crop = new Rect(parts[0], parts[1], parts[2], parts[3]);
                });
                break;
            case ToolId.CompressImage:
                AddSlider(stack, Lang.T("Quality", "Kalite"), 0.3, 0.9, value => request.Quality = value);
                break;
            case ToolId.AnnotateImage:
                Box(stack, Lang.T("Text", "Metin"), "Orange", text => request.Text = text);
                Box(stack, Lang.T("Color", "Renk"), "#F26B1D", text => request.Color = text);
                break;
            case ToolId.RedactImage:
            case ToolId.RedactVideo:
                Box(stack, Lang.T("Style", "Biçim"), "pixelate", text => request.RedactStyle = text);
                break;
            case ToolId.AddBackground:
                Box(stack, Lang.T("Color", "Renk"), "#FFFFFF", text => request.Background = text);
                break;
            case ToolId.ResizeImage:
                Box(stack, Lang.T("Width", "Genişlik"), "1280", text => request.Width = int.Parse(text));
                Box(stack, Lang.T("Height", "Yükseklik"), "720", text => request.Height = int.Parse(text));
                break;
            case ToolId.RotateImage:
            case ToolId.OrganizePdf:
                Box(stack, Lang.T("Quarter turns", "Çeyrek tur"), "1", text => request.QuartersClockwise = int.Parse(text));
                if (tool == ToolId.OrganizePdf) Box(stack, Lang.T("Page order", "Sayfa sırası"), "", text => request.PageOrder = text);
                break;
            case ToolId.SplitPdf:
                Box(stack, Lang.T("every, ranges, chunks", "every, ranges, chunks"), "every", text => request.SplitKind = text);
                Box(stack, Lang.T("Pages", "Sayfalar"), "all", text => request.PageSelection = text);
                break;
            case ToolId.TrimVideo:
            case ToolId.TrimAudio:
            case ToolId.BleepAudio:
            case ToolId.VideoFrames:
            case ToolId.SplitVideo:
                startBox = Box(stack, Lang.T("Start seconds", "Başlangıç"), "0", text => request.Start = double.Parse(text, CultureInfo.InvariantCulture));
                endBox = Box(stack, Lang.T("End seconds", "Bitiş"), "1", text => request.End = double.Parse(text, CultureInfo.InvariantCulture));
                playhead = new Slider { Minimum = 0, Maximum = 600, Value = 0, Width = 280 };
                stack.Children.Add(new TextBlock { Text = Lang.T("Playhead", "Oynatma") });
                stack.Children.Add(playhead);
                if (tool == ToolId.BleepAudio) stack.Children.Add(Check(Lang.T("Tone", "Ton"), value => request.BleepTone = value));
                break;
            case ToolId.VideoSpeed:
                Box(stack, Lang.T("Speed", "Hız"), "1", text => request.Speed = double.Parse(text));
                break;
            case ToolId.CompressVideo:
                Box(stack, Lang.T("small, balanced, high", "small, balanced, high"), "balanced", text => request.VideoQuality = text);
                break;
            case ToolId.NormalizeAudio:
                Box(stack, "dB", "-1", text => request.NormalizeDb = double.Parse(text));
                break;
            case ToolId.AudioChannels:
                stack.Children.Add(Check(Lang.T("Mono", "Mono"), value => request.ToMono = value));
                break;
            case ToolId.Metadata:
                foreach (var field in OrangeStudio.Metadata(paths[0]))
                    stack.Children.Add(new TextBlock { Text = field.Key + ": " + field.Value, TextWrapping = Avalonia.Media.TextWrapping.Wrap });
                break;
        }
    }

    async Task Apply()
    {
        try
        {
            if (tool == ToolId.RedactImage && request.Regions.Count == 0)
                request.Regions = VisionStudio.Faces(paths[0]).Concat(VisionStudio.TextRegions(paths[0])).ToList();
            status.Text = Lang.T("Working…", "Çalışıyor…");
            var outputs = tool == ToolId.Metadata
                ? await MetadataStudio.Strip(paths[0], CancellationToken.None)
                : await OrangeStudio.RunAsync(tool, paths, request);
            Session.Current.Remember(MainWindow.ToolTitle(tool), outputs, true);
            status.Text = string.Join("\n", outputs);
        }
        catch (Exception error)
        {
            status.Text = error.Message;
        }
    }

    void AddSlider(StackPanel stack, string title, double min, double max, Action<double> set)
    {
        var slider = new Slider { Minimum = min, Maximum = max, Value = 0, Width = 280 };
        adjustments.Add(slider);
        slider.PropertyChanged += (_, eventArgs) =>
        {
            if (eventArgs.Property == Slider.ValueProperty) set(slider.Value);
        };
        stack.Children.Add(new TextBlock { Text = title });
        stack.Children.Add(slider);
    }

    static TextBox Box(StackPanel stack, string title, string value, Action<string> set)
    {
        var box = new TextBox { Text = value };
        box.TextChanged += (_, _) =>
        {
            try { set(box.Text ?? ""); } catch { /* The apply button reports a bad value. */ }
        };
        set(value);
        stack.Children.Add(new TextBlock { Text = title });
        stack.Children.Add(box);
        return box;
    }

    static CheckBox Check(string title, Action<bool> set)
    {
        var box = new CheckBox { Content = title };
        box.IsCheckedChanged += (_, _) => set(box.IsChecked == true);
        return box;
    }
}

public class ShelfWindow : Window
{
    public ShelfWindow()
    {
        Title = Lang.T("Shelf", "Raf");
        Width = 320;
        Height = 420;
        Topmost = true;
        var list = new ListBox();
        foreach (var path in Session.Current.Shelf) list.Items.Add(path);
        list.DoubleTapped += (_, _) => { if (list.SelectedItem is string path) SystemActions.Reveal(path); };
        Content = list;
    }
}
