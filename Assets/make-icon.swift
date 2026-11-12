// 產生 RouteManager 的 App 圖示（1024x1024 PNG）
// 用法：swift Assets/make-icon.swift <輸出.png>
// 圖案：藍色圓角方塊上，三個節點以路徑相連，終點有箭頭，代表「路由」。
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS 圖示格線：內容區 824x824，置中，圓角約 185
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// 陰影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
              color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(bodyPath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

// 漸層底色
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(red: 0.18, green: 0.56, blue: 1.00, alpha: 1).cgColor,
                               NSColor(red: 0.05, green: 0.24, blue: 0.62, alpha: 1).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S - inset), end: CGPoint(x: 0, y: inset), options: [])

// 淡淡的格線，像網路拓樸圖底
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.07).cgColor)
ctx.setLineWidth(4)
var g: CGFloat = inset + 103
while g < S - inset {
    ctx.move(to: CGPoint(x: g, y: inset)); ctx.addLine(to: CGPoint(x: g, y: S - inset))
    ctx.move(to: CGPoint(x: inset, y: g)); ctx.addLine(to: CGPoint(x: S - inset, y: g))
    g += 103
}
ctx.strokePath()
ctx.restoreGState()

// 節點位置（座標原點在左下）
let a = CGPoint(x: 290, y: 330)   // 起點
let b = CGPoint(x: 512, y: 640)   // 中繼（閘道）
let c = CGPoint(x: 735, y: 400)   // 終點

// 虛線：另一條備援路徑
ctx.saveGState()
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
ctx.setLineWidth(18)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 44])
ctx.move(to: a); ctx.addLine(to: c)
ctx.strokePath()
ctx.restoreGState()

// 主路徑
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14,
              color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(40)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c)
ctx.strokePath()

// 終點箭頭（沿 b→c 方向）
let dx = c.x - b.x, dy = c.y - b.y
let len = sqrt(dx * dx + dy * dy)
let ux = dx / len, uy = dy / len
let tip = CGPoint(x: c.x + ux * 95, y: c.y + uy * 95)
let back: CGFloat = 105, half: CGFloat = 70
let base = CGPoint(x: tip.x - ux * back, y: tip.y - uy * back)
ctx.move(to: tip)
ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
ctx.closePath()
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

// 節點
func node(_ p: CGPoint, r: CGFloat, fill: NSColor) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    ctx.restoreGState()
    let ir = r * 0.55
    ctx.setFillColor(fill.cgColor)
    ctx.fillEllipse(in: CGRect(x: p.x - ir, y: p.y - ir, width: ir * 2, height: ir * 2))
}
node(a, r: 62, fill: NSColor(red: 0.20, green: 0.78, blue: 0.45, alpha: 1))  // 綠：來源
node(b, r: 74, fill: NSColor(red: 1.00, green: 0.62, blue: 0.10, alpha: 1))  // 橘：閘道
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
