using System.Diagnostics;
using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Threading;

namespace Orange.App;

public sealed class DragWatcher
{
    readonly Window owner;
    readonly DispatcherTimer timer;
    bool dragging;
    string[] files = [];
    WheelMode? mode;
    WheelWindow? wheel;
    Window? capture;

    public DragWatcher(Window owner)
    {
        this.owner = owner;
        timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        timer.Tick += (_, _) => Tick();
    }

    public void Start() => timer.Start();
    public void Stop() => timer.Stop();

    void Tick()
    {
        if (!Session.Current.WheelEnabled) return;
        var down = NativeInput.LeftButton();
        if (!down)
        {
            if (dragging) End();
            return;
        }
        dragging = true;
        var wanted = WheelKeys.Mode(NativeInput.Shift(), NativeInput.Control(), NativeInput.Alt());
        if (wanted is null)
        {
            mode = null;
            wheel?.Close();
            wheel = null;
            capture?.Close();
            capture = null;
            return;
        }
        if (files.Length == 0)
        {
            EnsureCapture();
            return;
        }
        if (mode != wanted || wheel is null)
        {
            mode = wanted;
            wheel?.Close();
            var cursor = NativeInput.Cursor();
            wheel = new WheelWindow(files, wanted.Value);
            wheel.Position = new Avalonia.PixelPoint((int)cursor.X - 180, (int)cursor.Y - 180);
            wheel.Show();
        }
    }

    void EnsureCapture()
    {
        if (capture is not null) return;
        if (OperatingSystem.IsLinux() && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WAYLAND_DISPLAY"))) return;
        capture = new Window
        {
            Width = 8,
            Height = 8,
            SystemDecorations = SystemDecorations.None,
            ShowInTaskbar = false,
            Topmost = true,
            Background = Avalonia.Media.Brushes.Transparent,
            Opacity = 0.01
        };
        DragDrop.SetAllowDrop(capture, true);
        capture.AddHandler(DragDrop.DragEnterEvent, (_, eventArgs) =>
        {
            files = eventArgs.Data.GetFiles()?.Select(file => file.Path.LocalPath).Where(File.Exists).ToArray() ?? [];
        });
        var cursor = NativeInput.Cursor();
        capture.Position = new Avalonia.PixelPoint((int)cursor.X, (int)cursor.Y);
        capture.Show();
    }

    void End()
    {
        dragging = false;
        files = [];
        mode = null;
        capture?.Close();
        capture = null;
    }
}

public static class NativeInput
{
    public static bool LeftButton() => OperatingSystem.IsWindows() ? (GetAsyncKeyState(0x01) & 0x8000) != 0 : X11.Button(1);
    public static bool Shift() => OperatingSystem.IsWindows() ? (GetAsyncKeyState(0x10) & 0x8000) != 0 : X11.Key(0xFFE1) || X11.Key(0xFFE2);
    public static bool Control() => OperatingSystem.IsWindows() ? (GetAsyncKeyState(0x11) & 0x8000) != 0 : X11.Key(0xFFE3) || X11.Key(0xFFE4);
    public static bool Alt() => OperatingSystem.IsWindows() ? (GetAsyncKeyState(0x12) & 0x8000) != 0 : X11.Key(0xFFE9) || X11.Key(0xFFEA);
    public static (int X, int Y) Cursor() => OperatingSystem.IsWindows() ? WinCursor() : X11.Pointer();

    [DllImport("user32.dll")]
    static extern short GetAsyncKeyState(int key);

    [DllImport("user32.dll")]
    static extern bool GetCursorPos(out WinPoint point);

    static (int X, int Y) WinCursor()
    {
        GetCursorPos(out var point);
        return (point.X, point.Y);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct WinPoint { public int X; public int Y; }
}

static class X11
{
    static IntPtr display;
    public static bool Button(int button) => Query(out _, out _, out var mask) && (mask & (0x100 << button)) != 0;
    public static (int X, int Y) Pointer() => Query(out var x, out var y, out _) ? (x, y) : (400, 400);
    public static bool Key(int keysym)
    {
        if (!OperatingSystem.IsLinux()) return false;
        if (display == IntPtr.Zero) display = XOpenDisplay(null);
        if (display == IntPtr.Zero) return false;
        var code = XKeysymToKeycode(display, (nuint)keysym);
        if (code == 0) return false;
        var keys = new byte[32];
        XQueryKeymap(display, keys);
        return (keys[code / 8] & (1 << (code % 8))) != 0;
    }

    static bool Query(out int x, out int y, out int mask)
    {
        x = y = mask = 0;
        if (!OperatingSystem.IsLinux()) return false;
        if (display == IntPtr.Zero) display = XOpenDisplay(null);
        if (display == IntPtr.Zero) return false;
        var root = XDefaultRootWindow(display);
        return XQueryPointer(display, root, out _, out _, out x, out y, out _, out _, out mask);
    }

    [DllImport("libX11")]
    static extern IntPtr XOpenDisplay(string? name);
    [DllImport("libX11")]
    static extern IntPtr XDefaultRootWindow(IntPtr display);
    [DllImport("libX11")]
    static extern bool XQueryPointer(IntPtr display, IntPtr window, out IntPtr root, out IntPtr child, out int rootX, out int rootY, out int winX, out int winY, out int mask);
    [DllImport("libX11")]
    static extern int XKeysymToKeycode(IntPtr display, nuint keysym);
    [DllImport("libX11")]
    static extern int XQueryKeymap(IntPtr display, byte[] keys);
}

public static class SystemActions
{
    public static IReadOnlyList<string> Run(ActionId action, IReadOnlyList<string> paths)
    {
        switch (action)
        {
            case ActionId.Float:
                new ShelfWindow().Show();
                return paths;
            case ActionId.Copy:
                return paths.Select(path => OrangeStudio.CopyTo(path, OutputLocation.Downloads())).ToArray();
            case ActionId.Move:
                return paths.Select(path => OrangeStudio.MoveTo(path, OutputLocation.Downloads())).ToArray();
            case ActionId.CopyPath:
                TextCopy(string.Join(Environment.NewLine, paths));
                return paths;
            case ActionId.Duplicate:
                return paths.Select(OrangeStudio.Duplicate).ToArray();
            case ActionId.Reveal:
                foreach (var path in paths) Reveal(path);
                return paths;
            case ActionId.Share:
                foreach (var path in paths) Share(path);
                return paths;
            case ActionId.Zip:
                return OrangeStudio.Zip(paths);
            case ActionId.OpenTerminal:
                OpenTerminal(paths[0]);
                return paths;
            default:
                return paths;
        }
    }

    public static void Reveal(string path)
    {
        if (OperatingSystem.IsWindows()) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
        else Process.Start(new ProcessStartInfo("xdg-open", $"\"{Path.GetDirectoryName(path)}\"") { UseShellExecute = false });
    }

    public static void Share(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true, Verb = "open" });
            return;
        }
        var portal = new ProcessStartInfo("xdg-open", path) { UseShellExecute = false };
        Process.Start(portal);
    }

    public static void OpenTerminal(string path)
    {
        var directory = Directory.Exists(path) ? path : Path.GetDirectoryName(path) ?? Environment.CurrentDirectory;
        if (OperatingSystem.IsWindows()) Process.Start(new ProcessStartInfo("cmd.exe", $"/K cd /d \"{directory}\"") { UseShellExecute = true });
        else Process.Start(new ProcessStartInfo("x-terminal-emulator", $"--working-directory=\"{directory}\"") { UseShellExecute = false });
    }

    static void TextCopy(string text)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                var start = new ProcessStartInfo("clip") { RedirectStandardInput = true, UseShellExecute = false, CreateNoWindow = true };
                using var process = Process.Start(start);
                process?.StandardInput.Write(text);
            }
            else
            {
                var start = new ProcessStartInfo("xclip", "-selection clipboard") { RedirectStandardInput = true, UseShellExecute = false };
                using var process = Process.Start(start);
                process?.StandardInput.Write(text);
            }
        }
        catch
        {
            var file = Path.Combine(Path.GetTempPath(), "orange-path.txt");
            File.WriteAllText(file, text);
        }
    }
}

public static class LoginItem
{
    public static void Apply(bool enabled)
    {
        if (OperatingSystem.IsWindows())
        {
            var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
            if (key is null) return;
            if (enabled) key.SetValue("Orange", $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue("Orange", false);
        }
        else if (OperatingSystem.IsLinux())
        {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config", "autostart");
            Directory.CreateDirectory(directory);
            var file = Path.Combine(directory, "orange.desktop");
            if (!enabled)
            {
                if (File.Exists(file)) File.Delete(file);
                return;
            }
            File.WriteAllText(file, $"""
                [Desktop Entry]
                Type=Application
                Name=Orange
                Exec={Environment.ProcessPath}
                X-GNOME-Autostart-enabled=true
                """);
        }
    }
}
