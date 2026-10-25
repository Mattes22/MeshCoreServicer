// Original geometric app icon, rendered with AppKit. No external artwork.
import AppKit
let target = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
let shape = NSBezierPath(roundedRect:NSRect(x:56,y:56,width:912,height:912),xRadius:204,yRadius:204)
NSGradient(starting:NSColor(red:0.035,green:0.23,blue:0.23,alpha:1),ending:NSColor(red:0.03,green:0.57,blue:0.49,alpha:1))!.draw(in:shape,angle:-40)
let points = [NSPoint(x:295,y:682),NSPoint(x:745,y:604),NSPoint(x:490,y:292)]
let lines = NSBezierPath(); lines.lineWidth = 38; lines.lineCapStyle = .round
lines.move(to:points[0]); lines.line(to:points[1]); lines.line(to:points[2]); lines.line(to:points[0])
NSColor(white:1,alpha:0.37).setStroke(); lines.stroke()
for p in points {
    NSColor.white.setFill(); NSBezierPath(ovalIn:NSRect(x:p.x-72,y:p.y-72,width:144,height:144)).fill()
    NSColor(red:0.05,green:0.37,blue:0.33,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:p.x-34,y:p.y-34,width:68,height:68)).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:target))
