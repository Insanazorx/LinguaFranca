import AppKit
import Foundation
import ImageIO

// One original closed-book drawing for both platform icons. No external artwork.
let output=URL(fileURLWithPath:CommandLine.arguments[1])
func png(pixels:Int,mac:Bool) -> Data {
    let alpha=mac ? CGImageAlphaInfo.premultipliedLast:CGImageAlphaInfo.noneSkipLast
    let canvas=CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:alpha.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    defer {NSGraphicsContext.restoreGraphicsState()}
    let context=NSGraphicsContext(cgContext:canvas,flipped:false)
    NSGraphicsContext.current=context
    context.cgContext.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
    let green=NSColor(srgbRed:0.17,green:0.35,blue:0.28,alpha:1)
    green.setFill()
    if mac {NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:200,yRadius:200).fill()}
    else {NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)).fill()}

    // Page block and a rounded front cover with a visible binding and title lines.
    NSColor(srgbRed:0.80,green:0.85,blue:0.79,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:294,y:226,width:446,height:580),xRadius:48,yRadius:48).fill()
    NSColor(srgbRed:0.98,green:0.97,blue:0.91,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:312,y:246,width:406,height:74),xRadius:24,yRadius:24).fill()
    NSBezierPath(roundedRect:NSRect(x:294,y:302,width:446,height:514),xRadius:40,yRadius:40).fill()
    let binding=NSBezierPath()
    binding.move(to:NSPoint(x:364,y:324));binding.line(to:NSPoint(x:364,y:794))
    binding.lineWidth=12;binding.lineCapStyle = .round
    green.withAlphaComponent(0.40).setStroke();binding.stroke()
    for (y,width) in [(646.0,220.0),(576.0,172.0),(506.0,204.0)] {
        let line=NSBezierPath();line.move(to:NSPoint(x:420,y:y));line.line(to:NSPoint(x:420+width,y:y))
        line.lineWidth=24;line.lineCapStyle = .round
        green.setStroke();line.stroke()
    }
    let pages=NSBezierPath();pages.move(to:NSPoint(x:366,y:282));pages.line(to:NSPoint(x:694,y:282))
    pages.lineWidth=8;pages.lineCapStyle = .round
    green.withAlphaComponent(0.32).setStroke();pages.stroke()
    let data=NSMutableData()
    let destination=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(destination,canvas.makeImage()!,nil)
    precondition(CGImageDestinationFinalize(destination),"Could not encode the icon")
    return data as Data
}
let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".iconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:folder)}
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let name="icon_\(size)x\(size)\(scale == 2 ? "@2x":"").png"
        try png(pixels:pixels,mac:true).write(to:folder.appendingPathComponent(name))
    }
}
try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");process.arguments=["-c","icns",folder.path,"-o",output.path]
try process.run();process.waitUntilExit()
if process.terminationStatus != 0 {exit(process.terminationStatus)}
if CommandLine.arguments.count>2 {
    let ios=URL(fileURLWithPath:CommandLine.arguments[2])
    try FileManager.default.createDirectory(at:ios.deletingLastPathComponent(),withIntermediateDirectories:true)
    try png(pixels:1024,mac:false).write(to:ios)
}
