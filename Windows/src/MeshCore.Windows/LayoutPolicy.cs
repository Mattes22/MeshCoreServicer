using System;

namespace MeshCore.Windows;
internal static class LayoutPolicy
{
    public static int Columns(double width, double minimum, int count)
    {
        if (count <= 0) return 1;
        if (double.IsPositiveInfinity(width)) return count;
        if (!double.IsFinite(width) || width <= 0) return 1;
        return Math.Clamp((int)Math.Min(count, Math.Floor((width + 16) / (Math.Max(1, minimum) + 16))), 1, count);
    }
    public static bool Compact(double width) => width < 1120;
    public static double WorkspaceHeight(int section, double width, double viewport)
    {
        double floor = section switch { 1 => width < 800 ? 1120 : 820, 2 => width < 820 ? 1120 : 800, 4 => width < 740 ? 1280 : 940, _ => 0 };
        return Math.Max(floor, double.IsFinite(viewport) ? Math.Max(0, viewport) : 0);
    }
    public static int ValidScale(int percent) => percent is 100 or 115 or 130 or 150 ? percent : 100;
}
