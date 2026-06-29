import AppKit

// Render a 1024x1024 app icon matching HomeView: dark refracting backdrop with a
// soft emerald glow up top, and a crown.fill filled with the emerald accent gradient.

let S: CGFloat = 1024
let accent = NSColor(srgbRed: 0.20, green: 0.83, blue: 0.60, alpha: 1)
let accentSoft = NSColor(srgbRed: 0.20, green: 0.83, blue: 0.60, alpha: 0.65)

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!
ctx.imageInterpolation = .high
let full = NSRect(x: 0, y: 0, width: S, height: S)

// Background: vertical dark gradient (note: AppKit y is bottom-up, so darkest at bottom).
let bg = NSGradient(colors: [
    NSColor(srgbRed: 0.02, green: 0.03, blue: 0.03, alpha: 1),
    NSColor(srgbRed: 0.04, green: 0.06, blue: 0.06, alpha: 1),
    NSColor(srgbRed: 0.07, green: 0.10, blue: 0.10, alpha: 1),
])!
bg.draw(in: full, angle: 90)

// Emerald glow near the top.
let glow = NSGradient(colors: [accent.withAlphaComponent(0.22), accent.withAlphaComponent(0.0)])!
glow.draw(in: full, relativeCenterPosition: NSPoint(x: 0.0, y: 0.55))

// Crown symbol, filled with the accent gradient via destinationIn masking.
let cfg = NSImage.SymbolConfiguration(pointSize: 600, weight: .semibold)
guard let crown = NSImage(systemSymbolName: "crown.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {
    fatalError("crown.fill unavailable")
}
let cs = crown.size
let scale = min(620 / cs.width, 620 / cs.height)
let cw = cs.width * scale, ch = cs.height * scale
let crownRect = NSRect(x: (S - cw) / 2, y: (S - ch) / 2 + 24, width: cw, height: ch)

let tinted = NSImage(size: NSSize(width: cw, height: ch))
tinted.lockFocus()
let localRect = NSRect(x: 0, y: 0, width: cw, height: ch)
NSGradient(colors: [accent, accentSoft])!.draw(in: localRect, angle: -45)
crown.draw(in: localRect, from: .zero, operation: .destinationIn, fraction: 1)
tinted.unlockFocus()

// Soft glow shadow behind the crown.
let sh = NSShadow()
sh.shadowColor = accent.withAlphaComponent(0.55)
sh.shadowBlurRadius = 70
sh.shadowOffset = .zero
sh.set()
tinted.draw(in: crownRect, from: .zero, operation: .sourceOver, fraction: 1)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("encode failed")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
