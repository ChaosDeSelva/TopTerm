import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894), xRadius: 195, yRadius: 195)
NSGradient(starting: NSColor(srgbRed: 0.14, green: 0.18, blue: 0.22, alpha: 1),
           ending: NSColor(srgbRed: 0.045, green: 0.065, blue: 0.09, alpha: 1))!.draw(in: tile, angle: -90)
NSColor(srgbRed: 0.46, green: 0.85, blue: 0.72, alpha: 1).setStroke()
let line = NSBezierPath()
line.lineWidth = 35
line.lineCapStyle = .round
line.move(to: NSPoint(x: 245, y: 740))
line.line(to: NSPoint(x: 780, y: 740))
line.stroke()
let prompt = NSBezierPath()
prompt.lineWidth = 55
prompt.lineCapStyle = .round
prompt.lineJoinStyle = .round
prompt.move(to: NSPoint(x: 285, y: 565))
prompt.line(to: NSPoint(x: 425, y: 450))
prompt.line(to: NSPoint(x: 285, y: 335))
prompt.stroke()
let cursor = NSBezierPath()
cursor.lineWidth = 48
cursor.lineCapStyle = .round
cursor.move(to: NSPoint(x: 530, y: 330))
cursor.line(to: NSPoint(x: 730, y: 330))
cursor.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
