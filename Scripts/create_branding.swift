import AppKit
import Foundation

// Original vector geometry. No font or stock-symbol outline is used for the mark.
let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let branding = root.appendingPathComponent("Branding",isDirectory:true)
let assets = root.appendingPathComponent("Tempo/Resources/Assets.xcassets",isDirectory:true)
try FileManager.default.createDirectory(at:branding,withIntermediateDirectories:true)
let geometry = "M 252 302 H 772 M 488 302 V 618 C 488 716 548 752 636 752 H 714"
let ink = "#10272B"
let teal = "#50DCC8"
let svgMark = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><path d="\(geometry)" fill="none" stroke="\(teal)" stroke-width="88" stroke-linecap="round" stroke-linejoin="round"/></svg>
"""
let svgIcon = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="\(ink)"/><path d="\(geometry)" fill="none" stroke="\(teal)" stroke-width="88" stroke-linecap="round" stroke-linejoin="round"/></svg>
"""
try Data(svgMark.utf8).write(to:branding.appendingPathComponent("tempo-mark.svg"))
try Data(svgIcon.utf8).write(to:branding.appendingPathComponent("tempo-app-icon.svg"))

func drawMark(_ context:CGContext, size:CGFloat, color:CGColor) {
    context.saveGState();context.scaleBy(x:size/1024,y:size/1024)
    // CGContext's image space is bottom-up; mirror the SVG's coordinates.
    context.translateBy(x:0,y:1024);context.scaleBy(x:1,y:-1)
    context.setStrokeColor(color);context.setLineWidth(88);context.setLineCap(.round);context.setLineJoin(.round)
    context.move(to:CGPoint(x:252,y:302));context.addLine(to:CGPoint(x:772,y:302));context.strokePath()
    context.move(to:CGPoint(x:488,y:302));context.addLine(to:CGPoint(x:488,y:618));context.addCurve(to:CGPoint(x:636,y:752),control1:CGPoint(x:488,y:716),control2:CGPoint(x:548,y:752));context.addLine(to:CGPoint(x:714,y:752));context.strokePath();context.restoreGState()
}
let tealColor = CGColor(red:80/255,green:220/255,blue:200/255,alpha:1)
let inkColor = CGColor(red:16/255,green:39/255,blue:43/255,alpha:1)
func png(size:Int,background:CGColor?,mark:CGColor)->Data {
    let colorSpace=CGColorSpace(name:CGColorSpace.sRGB)!
    let context=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:colorSpace,bitmapInfo:(background == nil ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    if let background{context.setFillColor(background);context.fill(CGRect(x:0,y:0,width:size,height:size))}
    drawMark(context, size:CGFloat(size), color:mark)
    let rep=NSBitmapImageRep(cgImage:context.makeImage()!)
    return rep.representation(using:.png,properties:[:])!
}
let icon=png(size:1024,background:inkColor,mark:tealColor)
let mark=png(size:1024,background:nil,mark:tealColor)
try icon.write(to:branding.appendingPathComponent("tempo-app-icon-1024.png"))
try mark.write(to:branding.appendingPathComponent("tempo-mark-transparent.png"))
let iconSet=branding.appendingPathComponent("AppIcon.appiconset",isDirectory:true)
let logoSet=branding.appendingPathComponent("TempoMark.imageset",isDirectory:true)
for directory in [iconSet,logoSet]{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)}
try icon.write(to:iconSet.appendingPathComponent("Tempo.png"))
let iconJSON="""
{"images":[{"filename":"Tempo.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try Data(iconJSON.utf8).write(to:iconSet.appendingPathComponent("Contents.json"))
for (suffix,size) in [("",128),("@2x",256),("@3x",384)] {
    try png(size:size,background:nil,mark:CGColor(gray:1,alpha:1)).write(to:logoSet.appendingPathComponent("TempoMark\(suffix).png"))
}
let logoJSON="""
{"images":[{"filename":"TempoMark.png","idiom":"universal","scale":"1x"},{"filename":"TempoMark@2x.png","idiom":"universal","scale":"2x"},{"filename":"TempoMark@3x.png","idiom":"universal","scale":"3x"}],"info":{"author":"xcode","version":1},"properties":{"template-rendering-intent":"template"}}
"""
try Data(logoJSON.utf8).write(to:logoSet.appendingPathComponent("Contents.json"))
// Keep the exported Xcode-ready folders and app's catalog byte-identical.
for (source,name) in [(iconSet,"AppIcon.appiconset"),(logoSet,"TempoMark.imageset")] {
    let target=assets.appendingPathComponent(name,isDirectory:true)
    try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
    for file in try FileManager.default.contentsOfDirectory(at:source,includingPropertiesForKeys:nil) {
        try Data(contentsOf:file).write(to:target.appendingPathComponent(file.lastPathComponent))
    }
}
print("Generated SVG, transparent mark, opaque 1024px app icon and Xcode-ready asset folders")

let widgetAssets=root.appendingPathComponent("TempoWidgets/Assets.xcassets",isDirectory:true)
let widgetLogo=widgetAssets.appendingPathComponent("TempoMark.imageset",isDirectory:true)
try FileManager.default.createDirectory(at:widgetLogo,withIntermediateDirectories:true)
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to:widgetAssets.appendingPathComponent("Contents.json"))
for file in try FileManager.default.contentsOfDirectory(at:logoSet,includingPropertiesForKeys:nil){try Data(contentsOf:file).write(to:widgetLogo.appendingPathComponent(file.lastPathComponent))}
let wordmark="""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1800 600"><path d="\(geometry)" transform="translate(-10 -70) scale(.6)" fill="none" stroke="\(teal)" stroke-width="88" stroke-linecap="round" stroke-linejoin="round"/><text x="640" y="398" fill="\(ink)" font-family="system-ui,-apple-system,Helvetica,Arial,sans-serif" font-size="300" font-weight="600" letter-spacing="-12">tempo</text></svg>
"""
try Data(wordmark.utf8).write(to:branding.appendingPathComponent("tempo-wordmark.svg"))
