// 產生 dmg 安裝視窗的背景圖（600x400 點）
// 用法：swift Assets/make-dmg-bg.swift <輸出.png> <倍率 1 或 2>
// 版面要和 make-dmg.sh 的圖示座標對齊：App 在 (150,190)、應用程式在 (450,190)、先讀我在 (300,270)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"
let scale: CGFloat = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1
let W: CGFloat = 600, H: CGFloat = 400

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// 之後一律用「點」為單位、左上為原點，方便對 Finder 座標
ctx.translateBy(x: 0, y: H)
ctx.scaleBy(x: 1, y: -1)

// 亮色底，淡藍漸層
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 1).cgColor,
                               NSColor(red: 0.89, green: 0.93, blue: 0.99, alpha: 1).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])

// 文字（翻轉座標下畫字要再翻回來）
func text(_ s: String, center: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attr)
    let sz = str.size()
    ctx.saveGState()
    ctx.translateBy(x: center.x - sz.width / 2, y: center.y + sz.height / 2)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    str.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}
text("把「路由管理」拖到「應用程式」完成安裝", center: CGPoint(x: W / 2, y: 52), size: 18, weight: .semibold,
     color: NSColor(red: 0.10, green: 0.20, blue: 0.40, alpha: 1))

// 中間箭頭：兩圖示之間（x 225～375，y 190 是圖示中心）
let y: CGFloat = 190
let blue = NSColor(red: 0.18, green: 0.50, blue: 0.95, alpha: 1).cgColor
ctx.setStrokeColor(blue)
ctx.setLineWidth(6)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [1, 14])
ctx.move(to: CGPoint(x: 238, y: y)); ctx.addLine(to: CGPoint(x: 340, y: y))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.move(to: CGPoint(x: 366, y: y))
ctx.addLine(to: CGPoint(x: 340, y: y - 16))
ctx.addLine(to: CGPoint(x: 340, y: y + 16))
ctx.closePath()
ctx.setFillColor(blue)
ctx.fillPath()

// 底部提示
text("第一次開啟若被擋：在「應用程式」對它按右鍵 →「打開」", center: CGPoint(x: W / 2, y: 382), size: 12,
     weight: .regular, color: NSColor(red: 0.35, green: 0.40, blue: 0.50, alpha: 1))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
