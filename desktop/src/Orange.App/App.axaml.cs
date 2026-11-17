using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Platform;

namespace Orange.App;

public class App : Application
{
    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        Session.Current.Load();
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow();
            desktop.Exit += (_, _) => Session.Current.Save();
            try { AddTray(desktop); }
            catch { /* The window remains usable when the tray cannot be created. */ }
        }
        base.OnFrameworkInitializationCompleted();
    }

    static void AddTray(IClassicDesktopStyleApplicationLifetime desktop)
    {
        WindowIcon? icon = null;
        try { icon = new WindowIcon(AssetLoader.Open(new Uri("avares://Orange/Assets/AppIcon.png"))); }
        catch { /* The tray still works without an icon. */ }
        var tray = new TrayIcon { Icon = icon, ToolTipText = "Orange", IsVisible = true };
        void Show()
        {
            if (desktop.MainWindow is not { } window) return;
            window.Show();
            window.WindowState = WindowState.Normal;
            window.Activate();
        }
        tray.Clicked += (_, _) => Show();
        var open = new NativeMenuItem(Lang.T("Open", "Aç"));
        open.Click += (_, _) => Show();
        var quit = new NativeMenuItem(Lang.T("Quit", "Çıkış"));
        quit.Click += (_, _) => desktop.Shutdown();
        tray.Menu = new NativeMenu { open, quit };
    }
}
