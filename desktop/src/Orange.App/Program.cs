using System.Runtime.InteropServices;
using Avalonia;

namespace Orange.App;

static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        try
        {
            Directory.SetCurrentDirectory(AppContext.BaseDirectory);
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        catch (Exception error)
        {
            Report(error);
        }
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();

    static void Report(Exception error)
    {
        var text = error.ToString();
        try
        {
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Orange");
            Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, "startup.log"), text);
        }
        catch
        {
            // The message box still carries the reason.
        }
        if (OperatingSystem.IsWindows()) MessageBox(IntPtr.Zero, text, "Orange", 0x10);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
    static extern int MessageBox(IntPtr owner, string text, string caption, uint type);
}
