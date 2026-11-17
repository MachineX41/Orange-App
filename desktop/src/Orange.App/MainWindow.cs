using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;

namespace Orange.App;

public class MainWindow : Window
{
    readonly Border body = new();
    readonly TextBlock status = new() { Opacity = 0.7, Margin = new Thickness(16, 0, 16, 12) };
    readonly DragWatcher drag;

    public MainWindow()
    {
        Title = "Orange";
        Width = 1080;
        Height = 720;
        MinWidth = 860;
        MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = true;
        Background = Brush(Session.Current.Appearance);
        drag = new DragWatcher(this);
        Content = BuildShell();
        Opened += async (_, _) =>
        {
            drag.Start();
            if (!Session.Current.Onboarded) await ShowOnboarding();
        };
        Closed += (_, _) => drag.Stop();
        ShowSection(AppSection.Home);
    }

    Control BuildShell()
    {
        var side = new StackPanel { Spacing = 6, Width = 196, Margin = new Thickness(16) };
        side.Children.Add(new TextBlock { Text = "Orange", FontSize = 28, FontWeight = FontWeight.Bold, Foreground = Accent() });
        foreach (var section in new[] { AppSection.Home, AppSection.Download, AppSection.Library, AppSection.Shelf, AppSection.ImageTools, AppSection.VideoTools, AppSection.AudioTools, AppSection.PdfTools })
        {
            var button = new Button { Content = TitleOf(section), HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left };
            button.Click += (_, _) => ShowSection(section);
            side.Children.Add(button);
        }
        side.Children.Add(new Button { Content = Lang.T("Settings", "Ayarlar"), HorizontalAlignment = HorizontalAlignment.Stretch, Command = null });
        ((Button)side.Children[^1]).Click += async (_, _) => await ShowSettings();
        side.Children.Add(new Button { Content = Lang.T("Shortcuts", "Kısayollar") });
        ((Button)side.Children[^1]).Click += async (_, _) => await ShowShortcuts();

        var right = new DockPanel();
        DockPanel.SetDock(status, Dock.Bottom);
        right.Children.Add(status);
        right.Children.Add(body);
        var root = new Grid { ColumnDefinitions = new ColumnDefinitions("220,*") };
        root.Children.Add(side);
        Grid.SetColumn(right, 1);
        root.Children.Add(right);
        return root;
    }

    void ShowSection(AppSection section)
    {
        body.Child = section switch
        {
            AppSection.Home => Home(),
            AppSection.Download => Download(),
            AppSection.Library => Library(),
            AppSection.Shelf => Shelf(),
            AppSection.ImageTools => Tools(MediaKind.Image),
            AppSection.VideoTools => Tools(MediaKind.Video),
            AppSection.AudioTools => Tools(MediaKind.Audio),
            AppSection.PdfTools => Tools(MediaKind.Pdf),
            _ => Home()
        };
    }

    Control Home()
    {
        var stack = new StackPanel { Margin = new Thickness(28), Spacing = 14 };
        stack.Children.Add(new TextBlock { Text = Lang.T("Drop a file. Hold a key. Let go on a slice.", "Dosyayı sürükleyin. Bir tuşa basın. Dilime bırakın."), FontSize = 26, TextWrapping = TextWrapping.Wrap });
        stack.Children.Add(new TextBlock
        {
            Text = Lang.T(
                "Shift converts, Ctrl opens tools, Alt opens actions. On Wayland, use the buttons below.",
                "Shift dönüştürür, Ctrl araçları, Alt eylemleri açar. Wayland’da aşağıdaki düğmeleri kullanın."),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.8
        });
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(ActionButton(Lang.T("Open files", "Dosya aç"), OpenAndWheel));
        row.Children.Add(ActionButton(Lang.T("Convert", "Dönüştür"), () => OpenAndWheel(WheelMode.Convert)));
        row.Children.Add(ActionButton(Lang.T("Tools", "Araçlar"), () => OpenAndWheel(WheelMode.Tools)));
        row.Children.Add(ActionButton(Lang.T("Actions", "Eylemler"), () => OpenAndWheel(WheelMode.Actions)));
        stack.Children.Add(row);
        return stack;
    }

    Control Download()
    {
        var url = new TextBox { Watermark = "https://", MinWidth = 420 };
        var audio = new CheckBox { Content = Lang.T("Audio only", "Yalnızca ses") };
        var button = new Button { Content = Lang.T("Download", "İndir") };
        button.Click += async (_, _) =>
        {
            try
            {
                status.Text = Lang.T("Downloading…", "İndiriliyor…");
                var files = await OrangeStudio.DownloadAsync(url.Text ?? "", audio.IsChecked == true, OutputLocation.Downloads(), value => status.Text = $"{(int)(value * 100)}%", CancellationToken.None);
                Session.Current.Remember(Lang.T("Download", "İndirme"), files, true);
                status.Text = string.Join(", ", files.Select(Path.GetFileName));
            }
            catch (Exception error) { status.Text = error.Message; }
        };
        return new StackPanel { Margin = new Thickness(28), Spacing = 12, Children = { new TextBlock { Text = Lang.T("Download", "İndir"), FontSize = 26 }, url, audio, button } };
    }

    Control Library()
    {
        var list = new ListBox();
        foreach (var job in Session.Current.Jobs)
            list.Items.Add($"{job.When.LocalDateTime:g}  {(job.Success ? "●" : "○")}  {job.Title}");
        return new DockPanel { Margin = new Thickness(28), Children = { new TextBlock { Text = Lang.T("Library", "Kitaplık"), FontSize = 26 }, list } };
    }

    Control Shelf()
    {
        var list = new ListBox();
        foreach (var path in Session.Current.Shelf) list.Items.Add(path);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var reveal = new Button { Content = Lang.T("Reveal", "Göster") };
        reveal.Click += (_, _) => { if (list.SelectedItem is string path) SystemActions.Reveal(path); };
        var remove = new Button { Content = Lang.T("Remove", "Kaldır") };
        remove.Click += (_, _) =>
        {
            if (list.SelectedItem is string path)
            {
                Session.Current.Shelf.Remove(path);
                Session.Current.Save();
                ShowSection(AppSection.Shelf);
            }
        };
        var floating = new Button { Content = Lang.T("Floating shelf", "Yüzen raf") };
        floating.Click += (_, _) => new ShelfWindow().Show();
        row.Children.Add(reveal);
        row.Children.Add(remove);
        row.Children.Add(floating);
        var panel = new DockPanel { Margin = new Thickness(28) };
        DockPanel.SetDock(row, Dock.Bottom);
        panel.Children.Add(row);
        panel.Children.Add(new TextBlock { Text = Lang.T("Shelf", "Raf"), FontSize = 26 });
        panel.Children.Add(list);
        return panel;
    }

    Control Tools(MediaKind kind)
    {
        var stack = new StackPanel { Margin = new Thickness(28), Spacing = 8 };
        stack.Children.Add(new TextBlock { Text = TitleOf(kind), FontSize = 26 });
        foreach (var tool in Catalog.Tools(kind))
        {
            var button = new Button { Content = ToolTitle(tool), HorizontalAlignment = HorizontalAlignment.Left, MinWidth = 220 };
            button.Click += async (_, _) => await OpenEditor(tool);
            stack.Children.Add(button);
        }
        return new ScrollViewer { Content = stack };
    }

    async Task OpenAndWheel() => await OpenAndWheel(null);

    async Task OpenAndWheel(WheelMode? mode)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions { AllowMultiple = true });
        var paths = files.Select(file => file.Path.LocalPath).Where(File.Exists).ToArray();
        if (paths.Length == 0) return;
        if (mode is null)
        {
            status.Text = Lang.T("Hold Shift, Ctrl or Alt, then use the wheel.", "Shift, Ctrl veya Alt’a basıp çarkı kullanın.");
            new WheelWindow(paths, WheelMode.Convert).Show();
            return;
        }
        new WheelWindow(paths, mode.Value).Show();
    }

    async Task OpenEditor(ToolId tool)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions { AllowMultiple = tool.AcceptsMany() });
        var paths = files.Select(file => file.Path.LocalPath).Where(File.Exists).ToArray();
        if (paths.Length < tool.MinimumFiles()) return;
        new EditorWindow(tool, paths).Show();
    }

    async Task ShowOnboarding()
    {
        var text = new TextBlock
        {
            Text = Lang.T(
                "Orange keeps files on this computer. Nothing is uploaded. The wheel opens while you drag a file and hold Shift, Ctrl or Alt.",
                "Orange dosyaları bu bilgisayarda tutar. Hiçbir şey yüklenmez. Bir dosyayı sürüklerken Shift, Ctrl veya Alt’a basınca çark açılır."),
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 420
        };
        var dialog = new Window { Title = "Orange", Width = 520, Height = 280, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = new StackPanel { Margin = new Thickness(24), Spacing = 16, Children = { text, new Button { Content = Lang.T("Continue", "Devam"), HorizontalAlignment = HorizontalAlignment.Right } } } };
        ((Button)((StackPanel)dialog.Content).Children[1]).Click += (_, _) => dialog.Close();
        await dialog.ShowDialog(this);
        Session.Current.Onboarded = true;
        Session.Current.Save();
    }

    async Task ShowSettings()
    {
        var language = new ComboBox { ItemsSource = new[] { LanguageChoice.System, LanguageChoice.Turkish, LanguageChoice.English }, SelectedItem = Session.Current.Language };
        var appearance = new ComboBox { ItemsSource = new[] { AppearanceChoice.System, AppearanceChoice.Light, AppearanceChoice.Dark }, SelectedItem = Session.Current.Appearance };
        var launch = new CheckBox { Content = Lang.T("Open at login", "Girişte aç"), IsChecked = Session.Current.LaunchAtLogin };
        var wheel = new CheckBox { Content = Lang.T("Drag wheel", "Sürükleme çarkı"), IsChecked = Session.Current.WheelEnabled };
        var clear = new Button { Content = Lang.T("Clear history", "Geçmişi sil") };
        clear.Click += (_, _) => { Session.Current.Jobs.Clear(); Session.Current.Shelf.Clear(); };
        var save = new Button { Content = Lang.T("Save", "Kaydet") };
        var dialog = new Window
        {
            Title = Lang.T("Settings", "Ayarlar"),
            Width = 420,
            Height = 360,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Content = new StackPanel { Margin = new Thickness(20), Spacing = 10, Children = { language, appearance, launch, wheel, clear, save } }
        };
        save.Click += (_, _) =>
        {
            Session.Current.Language = (LanguageChoice)language.SelectedItem!;
            Session.Current.Appearance = (AppearanceChoice)appearance.SelectedItem!;
            Session.Current.LaunchAtLogin = launch.IsChecked == true;
            Session.Current.WheelEnabled = wheel.IsChecked == true;
            Lang.Choice = Session.Current.Language;
            LoginItem.Apply(Session.Current.LaunchAtLogin);
            Session.Current.Save();
            Background = Brush(Session.Current.Appearance);
            dialog.Close();
            ShowSection(AppSection.Home);
        };
        await dialog.ShowDialog(this);
    }

    async Task ShowShortcuts()
    {
        var text = Lang.T(
            "Ctrl+O open. Ctrl+1 home, Ctrl+2 download, Ctrl+3 library, Ctrl+4 shelf. Ctrl+E convert, Ctrl+T tools, Ctrl+J actions. In editors: Space plays, I sets the start, O sets the end, S cuts, M resets color, Enter applies, Esc closes.",
            "Ctrl+O aç. Ctrl+1 ana sayfa, Ctrl+2 indir, Ctrl+3 kitaplık, Ctrl+4 raf. Ctrl+E dönüştür, Ctrl+T araçlar, Ctrl+J eylemler. Düzenleyicide Space oynatır, I başlangıcı, O bitişi yazar, S keser, M rengi sıfırlar, Enter uygular, Esc kapatır.");
        var dialog = new Window { Width = 480, Height = 240, Title = Lang.T("Shortcuts", "Kısayollar"), WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = new TextBlock { Text = text, Margin = new Thickness(20), TextWrapping = TextWrapping.Wrap } };
        await dialog.ShowDialog(this);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyModifiers.HasFlag(KeyModifiers.Control))
        {
            switch (e.Key)
            {
                case Key.D1: ShowSection(AppSection.Home); break;
                case Key.D2: ShowSection(AppSection.Download); break;
                case Key.D3: ShowSection(AppSection.Library); break;
                case Key.D4: ShowSection(AppSection.Shelf); break;
                case Key.D5: ShowSection(AppSection.ImageTools); break;
                case Key.D6: ShowSection(AppSection.VideoTools); break;
                case Key.D7: ShowSection(AppSection.AudioTools); break;
                case Key.D8: ShowSection(AppSection.PdfTools); break;
                case Key.O: _ = OpenAndWheel(null); break;
                case Key.E: _ = OpenAndWheel(WheelMode.Convert); break;
                case Key.T: _ = OpenAndWheel(WheelMode.Tools); break;
                case Key.J: _ = OpenAndWheel(WheelMode.Actions); break;
                case Key.L: new ShelfWindow().Show(); break;
            }
        }
        base.OnKeyDown(e);
    }

    static Button ActionButton(string title, Func<Task> action)
    {
        var button = new Button { Content = title };
        button.Click += async (_, _) => await action();
        return button;
    }

    static string TitleOf(AppSection section) => section switch
    {
        AppSection.Home => Lang.T("Home", "Ana Sayfa"),
        AppSection.Download => Lang.T("Download", "İndir"),
        AppSection.Library => Lang.T("Library", "Kitaplık"),
        AppSection.Shelf => Lang.T("Shelf", "Raf"),
        AppSection.ImageTools => Lang.T("Images", "Görseller"),
        AppSection.VideoTools => Lang.T("Video", "Video"),
        AppSection.AudioTools => Lang.T("Audio", "Ses"),
        AppSection.PdfTools => Lang.T("PDF", "PDF"),
        _ => ""
    };

    static string TitleOf(MediaKind kind) => kind switch
    {
        MediaKind.Image => Lang.T("Images", "Görseller"),
        MediaKind.Video => Lang.T("Video", "Video"),
        MediaKind.Audio => Lang.T("Audio", "Ses"),
        MediaKind.Pdf => Lang.T("PDF", "PDF"),
        _ => kind.ToString()
    };

    public static string ToolTitle(ToolId tool) => tool switch
    {
        ToolId.AdjustImage => Lang.T("Adjust", "Düzenle"),
        ToolId.CropImage => Lang.T("Crop", "Kırp"),
        ToolId.CompressImage => Lang.T("Compress", "Sıkıştır"),
        ToolId.AnnotateImage => Lang.T("Annotate", "İşaretle"),
        ToolId.RedactImage => Lang.T("Redact", "Gizle"),
        ToolId.AddBackground => Lang.T("Background", "Arka plan"),
        ToolId.RemoveBackground => Lang.T("Remove background", "Arka planı kaldır"),
        ToolId.ResizeImage => Lang.T("Resize", "Boyutlandır"),
        ToolId.RotateImage => Lang.T("Rotate", "Döndür"),
        ToolId.Collage => Lang.T("Collage", "Kolaj"),
        ToolId.ImagesToPdf => Lang.T("Images to PDF", "Görsellerden PDF"),
        ToolId.MergePdf => Lang.T("Merge", "Birleştir"),
        ToolId.SplitPdf => Lang.T("Split", "Böl"),
        ToolId.OrganizePdf => Lang.T("Organize", "Sırala"),
        ToolId.CompressPdf => Lang.T("Compress", "Sıkıştır"),
        ToolId.TrimVideo or ToolId.TrimAudio => Lang.T("Trim", "Kes"),
        ToolId.CropVideo => Lang.T("Crop", "Kırp"),
        ToolId.CompressVideo => Lang.T("Compress", "Sıkıştır"),
        ToolId.VideoSpeed => Lang.T("Speed", "Hız"),
        ToolId.MuteVideo => Lang.T("Mute", "Sesi kapat"),
        ToolId.VideoFrames => Lang.T("Frame", "Kare"),
        ToolId.SplitVideo => Lang.T("Split", "Böl"),
        ToolId.RedactVideo => Lang.T("Redact", "Gizle"),
        ToolId.JoinVideos => Lang.T("Join", "Birleştir"),
        ToolId.NormalizeAudio => Lang.T("Normalize", "Normalleştir"),
        ToolId.AudioChannels => Lang.T("Channels", "Kanallar"),
        ToolId.BleepAudio => Lang.T("Bleep", "Bip"),
        ToolId.AudioToVideo => Lang.T("Visualizer", "Görselleştirici"),
        ToolId.Metadata => Lang.T("Metadata", "Meta veri"),
        ToolId.ReadQr => Lang.T("Read codes", "Kod oku"),
        ToolId.Unzip => Lang.T("Extract", "Aç"),
        _ => tool.ToString()
    };

    static IBrush Accent() => new SolidColorBrush(Color.Parse("#F26B1D"));

    static IBrush Brush(AppearanceChoice choice)
    {
        var dark = choice == AppearanceChoice.Dark || (choice == AppearanceChoice.System && Application.Current?.ActualThemeVariant == Avalonia.Styling.ThemeVariant.Dark);
        return new SolidColorBrush(dark ? Color.Parse("#161616") : Color.Parse("#E7E1D8"));
    }
}
