using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;

namespace Orange.App;

public class WheelWindow : Window
{
    readonly string[] files;
    WheelMode mode;
    int? highlight;

    public WheelWindow(IReadOnlyList<string> files, WheelMode mode)
    {
        this.files = files.ToArray();
        this.mode = mode;
        Width = 360;
        Height = 360;
        SystemDecorations = SystemDecorations.None;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        Topmost = true;
        CanResize = false;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = new WheelFace(this);
        PointerMoved += (_, eventArgs) =>
        {
            var point = eventArgs.GetPosition(this);
            highlight = Layout().IndexAt(new Point(point.X, point.Y));
            InvalidateVisual();
            ((WheelFace)Content!).InvalidateVisual();
        };
        AddHandler(DragDrop.DropEvent, OnDrop);
        DragDrop.SetAllowDrop(this, true);
    }

    public WheelLayout Layout() => new(new Point(180, 180), 108, 46, 168, Math.Max(1, Choices().Count));

    public IReadOnlyList<string> Labels() => Choices();

    public int? Highlight => highlight;

    public void Cycle(WheelMode next)
    {
        mode = next;
        highlight = null;
        ((WheelFace)Content!).InvalidateVisual();
    }

    void OnDrop(object? sender, DragEventArgs eventArgs)
    {
        var dropped = eventArgs.Data.GetFiles()?.Select(file => file.Path.LocalPath).Where(File.Exists).ToArray();
        var paths = dropped is { Length: > 0 } ? dropped : files;
        if (highlight is int index) _ = Apply(index, paths);
        Close();
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        if (highlight is int index) _ = Apply(index, files);
        Close();
        base.OnPointerReleased(e);
    }

    async Task Apply(int index, IReadOnlyList<string> paths)
    {
        try
        {
            var label = Choices()[index];
            IReadOnlyList<string> outputs = mode switch
            {
                WheelMode.Convert => await OrangeStudio.ConvertAsync(paths[0], Enum.Parse<ConvertTarget>(label, true)),
                WheelMode.Tools => await OrangeStudio.RunAsync(Enum.Parse<ToolId>(label, true), paths),
                _ => SystemActions.Run(Enum.Parse<ActionId>(label, true), paths)
            };
            Session.Current.Remember(label, outputs, true);
        }
        catch (Exception error)
        {
            Session.Current.Remember(error.Message, [], false);
        }
    }

    List<string> Choices() => mode switch
    {
        WheelMode.Convert => Catalog.CommonConvertTargets(files).Select(target => target.ToString()).ToList(),
        WheelMode.Tools => Catalog.CommonTools(files).Select(tool => tool.ToString()).ToList(),
        _ => Enum.GetNames<ActionId>().ToList()
    };
}

public class WheelFace : Control
{
    readonly WheelWindow window;
    public WheelFace(WheelWindow window) => this.window = window;

    public override void Render(DrawingContext context)
    {
        var labels = window.Labels();
        var layout = window.Layout();
        var center = new Avalonia.Point(layout.Center.X, layout.Center.Y);
        context.DrawEllipse(new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)), null, center, layout.OuterRadius, layout.OuterRadius);
        for (var index = 0; index < labels.Count; index++)
        {
            var point = layout.PointFor(index);
            var selected = window.Highlight == index;
            var brush = new SolidColorBrush(selected ? Color.Parse("#F26B1D") : Color.FromArgb(170, 28, 28, 30));
            context.DrawEllipse(brush, new Pen(new SolidColorBrush(Color.FromArgb(90, 255, 255, 255))), new Avalonia.Point(point.X, point.Y), 46, 46);
            var text = new FormattedText(Short(labels[index]), System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface("Inter"), 11, Brushes.White);
            context.DrawText(text, new Avalonia.Point(point.X - text.Width / 2, point.Y - text.Height / 2));
        }
    }

    static string Short(string name) => name.Length <= 10 ? name : name[..9];
}
