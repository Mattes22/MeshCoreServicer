using System;
using System.Windows;
using System.Windows.Controls;

namespace MeshCore.Windows;

// All dimensions are device-independent WPF units. PerMonitorV2 handles physical DPI;
// the user scale is applied once, to the shell, and changes its available layout width.
internal sealed class ResponsiveColumns : Grid
{
    private readonly double minimum;
    private int columns;
    public ResponsiveColumns(double minimumWidth, params UIElement[] children)
    {
        minimum = minimumWidth;
        foreach (var child in children) Children.Add(new Border { Child = child });
    }
    protected override Size MeasureOverride(Size constraint)
    {
        int count = LayoutPolicy.Columns(constraint.Width, minimum, Children.Count);
        if (count != columns)
        {
            columns = count; ColumnDefinitions.Clear(); RowDefinitions.Clear();
            for (int i = 0; i < count; i++) ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
            for (int i = 0; i < (Children.Count + count - 1) / count; i++) RowDefinitions.Add(new() { Height = GridLength.Auto });
            for (int i = 0; i < Children.Count; i++)
            {
                SetColumn(Children[i], i % count); SetRow(Children[i], i / count);
                ((Border)Children[i]).Margin = new(i % count == 0 ? 0 : 8, 0, i % count == count - 1 ? 0 : 8, 0);
            }
        }
        return base.MeasureOverride(constraint);
    }
}

internal sealed class ResponsiveHeading : Grid
{
    private readonly Border? actions;
    public ResponsiveHeading(UIElement text, UIElement? controls)
    {
        ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) }); ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        RowDefinitions.Add(new() { Height = GridLength.Auto }); RowDefinitions.Add(new() { Height = GridLength.Auto });
        Children.Add(text);
        if (controls != null) { actions = new Border { Child = controls, MaxWidth = 420, VerticalAlignment = VerticalAlignment.Center }; Children.Add(actions); }
    }
    protected override Size MeasureOverride(Size constraint)
    {
        if (actions != null)
        {
            bool stacked = constraint.Width < 740;
            SetColumn(actions, stacked ? 0 : 1); SetRow(actions, stacked ? 1 : 0);
            actions.Margin = stacked ? new(0, 12, 0, 0) : new(20, 0, 0, 0);
            actions.HorizontalAlignment = stacked ? HorizontalAlignment.Left : HorizontalAlignment.Stretch;
        }
        return base.MeasureOverride(constraint);
    }
}

// A narrow window keeps both panes usable, with independent scrolling. The outer
// workspace supplies enough height instead of compressing the thread or terminal.
internal sealed class ResponsiveSplit : Grid
{
    private readonly double sideWidth, breakpoint, stackedFirstHeight;
    private bool? stacked;
    public ResponsiveSplit(UIElement first, UIElement second, double side, double threshold, double firstHeight, bool sideOnRight = false)
    {
        sideWidth = side; breakpoint = threshold; stackedFirstHeight = firstHeight; SideOnRight = sideOnRight;
        Children.Add(first); Children.Add(second);
    }
    private bool SideOnRight { get; }
    protected override Size MeasureOverride(Size constraint)
    {
        bool narrow = constraint.Width < breakpoint;
        if (stacked != narrow)
        {
            stacked = narrow; ColumnDefinitions.Clear(); RowDefinitions.Clear();
            if (narrow)
            {
                ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
                RowDefinitions.Add(new() { Height = new(stackedFirstHeight) }); RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) });
            }
            else
            {
                ColumnDefinitions.Add(new() { Width = SideOnRight ? new(1, GridUnitType.Star) : new(sideWidth) });
                ColumnDefinitions.Add(new() { Width = SideOnRight ? new(sideWidth) : new(1, GridUnitType.Star) });
                RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) });
            }
            SetColumn(Children[1], narrow ? 0 : 1); SetRow(Children[1], narrow ? 1 : 0);
        }
        return base.MeasureOverride(constraint);
    }
}
