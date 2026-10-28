using Avalonia.Controls;
using Avalonia.Media;
namespace MeshCore.Linux;
internal static class NativeIcons {
    private static readonly string[] Data = [
        "M9,2 L9,8 M15,2 L15,8 M7,7 L17,7 L17,13 L14,16 L14,22 L10,22 L10,16 L7,13 Z",
        "M8,11 A4,4 0 1 0 8,3 A4,4 0 1 0 8,11 M2,21 L2,18 C2,13 14,13 14,18 L14,21 Z M16,4 C22,3 23,11 17,12 M17,15 C22,15 23,18 23,21",
        "M3,3 L17,3 Q19,3 19,5 L19,13 Q19,15 17,15 L9,15 L5,19 L5,15 L3,15 Q1,15 1,13 L1,5 Q1,3 3,3 M21,8 L23,8 L23,19 L20,19 L20,23 L16,19 L11,19",
        "M12,12 L12,23 M10,23 L14,23 M8,8 C5,11 5,15 8,18 M16,8 C19,11 19,15 16,18 M5,4 C0,9 0,17 5,22 M19,4 C24,9 24,17 19,22 M12,9 A2,2 0 1 0 12,13 A2,2 0 1 0 12,9",
        "M2,3 L22,3 L22,21 L2,21 Z M6,8 L10,12 L6,16 M12,16 L18,16",
        "M1,13 L6,13 L9,3 L12,22 L16,8 L18,13 L23,13",
        "M2,5 L22,5 M2,12 L22,12 M2,19 L22,19 M6,2 L6,8 M17,9 L17,15 M9,16 L9,22",
    ];
    public static Control Icon(int index) => new Avalonia.Controls.Shapes.Path { Data=Geometry.Parse(Data[index]),Width=22,Height=22,Stretch=Stretch.Uniform,Stroke=new SolidColorBrush(Color.Parse("#59BFAF")),StrokeThickness=1.8,VerticalAlignment=Avalonia.Layout.VerticalAlignment.Center };
}
