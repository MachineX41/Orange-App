namespace Orange;

public readonly record struct Point(double X, double Y);

public readonly record struct Size(double Width, double Height);

public readonly record struct Rect(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
    public static Rect Zero => new(0, 0, 0, 0);

    public Rect Intersection(Rect other)
    {
        var x1 = Math.Max(MinX, other.MinX);
        var y1 = Math.Max(MinY, other.MinY);
        var x2 = Math.Min(MaxX, other.MaxX);
        var y2 = Math.Min(MaxY, other.MaxY);
        if (x2 <= x1 || y2 <= y1) return Zero;
        return new Rect(x1, y1, x2 - x1, y2 - y1);
    }
}

public readonly record struct WheelLayout(Point Center, double RingRadius, double InnerRadius, double OuterRadius, int Count)
{
    public double SliceAngle => Count > 0 ? (2 * Math.PI) / Count : 0;

    /// <summary>Index 0 sits at twelve o'clock and indexes advance clockwise on screen.</summary>
    public double Angle(int index) => -Math.PI / 2 + index * SliceAngle;

    public Point PointFor(int index, double? radius = null)
    {
        if (Count <= 0) return Center;
        var theta = Angle(index);
        var r = radius ?? RingRadius;
        return new Point(Center.X + Math.Cos(theta) * r, Center.Y + Math.Sin(theta) * r);
    }

    /// <summary>Point uses a top-left origin with y growing downward.</summary>
    public int? IndexAt(Point point)
    {
        if (Count <= 0) return null;
        var dx = point.X - Center.X;
        var dy = point.Y - Center.Y;
        var distance = Math.Sqrt(dx * dx + dy * dy);
        if (distance < InnerRadius || distance > OuterRadius) return null;
        var delta = Math.Atan2(dy, dx) + Math.PI / 2;
        while (delta < 0) delta += 2 * Math.PI;
        while (delta >= 2 * Math.PI) delta -= 2 * Math.PI;
        var index = (int)Math.Round(delta / SliceAngle);
        index %= Count;
        return index;
    }
}

public static class CropMath
{
    public static Rect FittedRect(Size imageSize, Size viewSize)
    {
        if (imageSize.Width <= 0 || imageSize.Height <= 0 || viewSize.Width <= 0 || viewSize.Height <= 0)
            return Rect.Zero;
        var scale = Math.Min(viewSize.Width / imageSize.Width, viewSize.Height / imageSize.Height);
        var drawn = new Size(imageSize.Width * scale, imageSize.Height * scale);
        return new Rect((viewSize.Width - drawn.Width) / 2, (viewSize.Height - drawn.Height) / 2, drawn.Width, drawn.Height);
    }

    public static Rect NormalizedRect(Rect selection, Size imageSize, Size viewSize)
    {
        var fitted = FittedRect(imageSize, viewSize);
        if (fitted.Width <= 0 || fitted.Height <= 0) return Rect.Zero;
        var clipped = selection.Intersection(fitted);
        if (clipped.Width <= 0.5 || clipped.Height <= 0.5) return Rect.Zero;
        return new Rect(
            (clipped.MinX - fitted.MinX) / fitted.Width,
            (clipped.MinY - fitted.MinY) / fitted.Height,
            clipped.Width / fitted.Width,
            clipped.Height / fitted.Height);
    }

    /// <summary>Top-left normalized rect into Core Graphics pixel space (bottom-left origin).</summary>
    public static Rect PixelRect(Rect normalizedTopLeft, Size imageSize)
    {
        var width = normalizedTopLeft.Width * imageSize.Width;
        var height = normalizedTopLeft.Height * imageSize.Height;
        var x = normalizedTopLeft.X * imageSize.Width;
        var y = (1 - normalizedTopLeft.Y) * imageSize.Height - height;
        return new Rect(x, y, width, height);
    }

    /// <summary>Top-left normalized rect into top-left pixel space used by ImageMagick and Skia.</summary>
    public static Rect PixelRectTopLeft(Rect normalizedTopLeft, Size imageSize) => new(
        normalizedTopLeft.X * imageSize.Width,
        normalizedTopLeft.Y * imageSize.Height,
        normalizedTopLeft.Width * imageSize.Width,
        normalizedTopLeft.Height * imageSize.Height);
}
