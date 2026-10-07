// Vector source for Scripts/make_icon.py. Only the generated resource ships.
import AppKit
import ImageIO
import UniformTypeIdentifiers

func png(_ size: Int) -> Data {
    let context = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 256, y: CGFloat(size) / 256)
    context.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.055, alpha: 1))
    context.addPath(CGPath(roundedRect: CGRect(x: 12, y: 12, width: 232, height: 232),
                           cornerWidth: 52, cornerHeight: 52, transform: nil))
    context.fillPath()
    context.setFillColor(CGColor(red: 74 / 255, green: 158 / 255, blue: 1, alpha: 1))
    for (x, height) in [(66.0, 48.0), (101.0, 104.0)] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: 128 - height / 2,
                                                 width: 18, height: height),
                               cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.fillPath()
    }
    context.move(to: CGPoint(x: 146, y: 76))
    context.addLine(to: CGPoint(x: 204, y: 128))
    context.addLine(to: CGPoint(x: 146, y: 180))
    context.closePath()
    context.fillPath()
    let data = NSMutableData()
    let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(output))
    return data as Data
}

func length(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian
    return withUnsafeBytes(of: &big) { Data($0) }
}

var body = Data()
for (type, size) in [("icp5", 32), ("ic08", 256)] {
    let data = png(size)
    body.append(Data(type.utf8))
    body.append(length(data.count + 8))
    body.append(data)
}
var icon = Data("icns".utf8)
icon.append(length(body.count + 8))
icon.append(body)
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
try icon.write(to: destination, options: .atomic)
print("\(icon.count) bytes: \(destination.path)")
