using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;

namespace MeshCore.Windows;

// Native Shell_NotifyIcon: no embedded browser, service, or external notification dependency.
public sealed class Tray : IDisposable
{
    private const uint Callback = 0x8001;
    private readonly HwndSource source;
    private readonly Action show, exit;
    private Action? notificationClick;
    private IntPtr appIcon;
    private bool ownsIcon;
    private readonly uint taskbarCreated;
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct Data
    {
        public uint Size; public IntPtr Window; public uint Id, Flags, Callback; public IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Timeout;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string Title;
        public uint InfoFlags; public Guid Guid; public IntPtr BalloonIcon;
    }
    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool Notify(uint message, ref Data data);
    [DllImport("shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode)] private static extern uint ExtractIcon(string file, int index, IntPtr large, out IntPtr small, uint count);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll", EntryPoint = "LoadIconW")] private static extern IntPtr LoadIcon(IntPtr instance, IntPtr name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetForegroundWindow(IntPtr window);
    public Tray(Action show, Action exit)
    {
        this.show = show; this.exit = exit; if (Environment.ProcessPath is { } path && ExtractIcon(path, 0, IntPtr.Zero, out var extracted, 1) > 0 && extracted != IntPtr.Zero) { appIcon = extracted; ownsIcon = true; } else appIcon = LoadIcon(IntPtr.Zero, new IntPtr(32512)); source = new(new HwndSourceParameters("MeshCore Servicer notifications") { Width = 0, Height = 0, WindowStyle = 0 }); source.AddHook(Message); taskbarCreated = RegisterWindowMessage("TaskbarCreated"); Add();
    }
    private Data Base() => new() { Size = (uint)Marshal.SizeOf<Data>(), Window = source.Handle, Id = 1, Tip = "MeshCore Servicer", Info = "", Title = "" };
    private void Add() { var data = Base(); data.Flags = 7; data.Callback = Callback; data.Icon = appIcon; Notify(0, ref data); }
    private IntPtr Message(IntPtr window, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if ((uint)message == taskbarCreated) Add();
        if ((uint)message != Callback) return IntPtr.Zero;
        int action = lParam.ToInt32();
        if (action == 0x203) show();
        if (action == 0x405) { show(); notificationClick?.Invoke(); }
        if (action == 0x205)
        {
            SetForegroundWindow(source.Handle); ContextMenu menu = new(); MenuItem open = new() { Header = "Otevřít MeshCore Servicer" }; open.Click += (_, _) => show(); MenuItem quit = new() { Header = "Ukončit aplikaci" }; quit.Click += (_, _) => exit(); menu.Items.Add(open); menu.Items.Add(quit); menu.IsOpen = true;
        }
        return IntPtr.Zero;
    }
    public void Show(string title, string body, bool sound, Action clicked)
    { notificationClick = clicked; var data = Base(); data.Flags = 0x10; data.Title = title[..Math.Min(title.Length, 63)]; data.Info = body[..Math.Min(body.Length, 255)]; data.InfoFlags = 1u | (sound ? 0u : 0x10u); Notify(1, ref data); }
    public void Dispose() { var data = Base(); Notify(2, ref data); source.Dispose(); if (ownsIcon) DestroyIcon(appIcon); }
}
