// The system's Liquid Glass over a background, rendered offscreen
// (macOS 26: NSGlassEffectView in a window, then its layers drawn by
// CARenderer, as the window server draws them, with no screen capture):
// the references the drawn glass is tuned to (tests/ui/GlassTest.hx).
//   swiftc -O tests/ui/glass-reference.swift -o bin/glass-reference
//   glass-reference <background.png> <out.png> <scale> [dark] <glass>...
// each glass "x,y,w,h,radius,style,tint" in points (style 0 regular, 1
// clear; tint #rrggbbaa or -)
import AppKit
import Metal
import QuartzCore

let a = CommandLine.arguments
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let dark = a.count > 4 && a[4] == "dark"
app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
let bg = NSImage(contentsOfFile: a[1])!
let k = Double(a[3])!
let rep = bg.representations[0]
let W = Double(rep.pixelsWide) / k, H = Double(rep.pixelsHigh) / k
let win = NSWindow(contentRect: NSRect(x: -10000, y: 0, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
win.appearance = app.appearance
let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
root.wantsLayer = true
let back = CALayer()
back.frame = root.bounds
back.contents = bg.cgImage(forProposedRect: nil, context: nil, hints: nil)
back.contentsScale = k
root.layer!.addSublayer(back)
for g in a.dropFirst(dark ? 5 : 4) {
	let f = g.split(separator: ",").map(String.init)
	let x = Double(f[0])!, y = Double(f[1])!, w = Double(f[2])!, h = Double(f[3])!
	let v = NSGlassEffectView(frame: NSRect(x: x, y: H - y - h, width: w, height: h))
	v.cornerRadius = Double(f[4])!
	v.style = f[5] == "1" ? .clear : .regular
	if f[6] != "-" {
		let t = UInt32(f[6].dropFirst(), radix: 16)!
		v.tintColor = NSColor(srgbRed: Double(t >> 24 & 0xFF) / 255, green: Double(t >> 16 & 0xFF) / 255, blue: Double(t >> 8 & 0xFF) / 255, alpha: Double(t & 0xFF) / 255)
	}
	root.addSubview(v)
}
win.contentView = root
win.orderFrontRegardless()
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
// (the layers out of the window: CARenderer draws a tree of no other context)
win.contentView = NSView()
win.orderOut(nil)
let PW = Int(W * k), PH = Int(H * k)
let dev = MTLCreateSystemDefaultDevice()!
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: PW, height: PH, mipmapped: false)
td.usage = [.renderTarget, .shaderRead]
td.storageMode = .shared
let tex = dev.makeTexture(descriptor: td)!
let q = dev.makeCommandQueue()!
let r = CARenderer(mtlTexture: tex, options: [kCARendererMetalCommandQueue: q])
// (its own layer, scaled to pixels: CARenderer draws y up, the rows flipped below)
root.layer!.sublayerTransform = CATransform3DMakeScale(CGFloat(k), CGFloat(k), 1)
r.layer = root.layer!
r.bounds = CGRect(x: 0, y: 0, width: PW, height: PH)
CATransaction.flush()
for _ in 0..<4 {
	r.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
	r.addUpdate(r.bounds)
	r.render()
	r.endFrame()
}
let cb = q.makeCommandBuffer()!
cb.commit()
cb.waitUntilCompleted()
var px = [UInt8](repeating: 0, count: PW * PH * 4)
tex.getBytes(&px, bytesPerRow: PW * 4, from: MTLRegionMake2D(0, 0, PW, PH), mipmapLevel: 0)
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: PW, pixelsHigh: PH, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
	colorSpaceName: .deviceRGB, bytesPerRow: PW * 4, bitsPerPixel: 32)!
let dst = out.bitmapData!
for y in 0..<PH {
	for x in 0..<PW {
		let i = ((PH - 1 - y) * PW + x) * 4, o = (y * PW + x) * 4
		dst[o] = px[i + 2]
		dst[o + 1] = px[i + 1]
		dst[o + 2] = px[i]
		dst[o + 3] = 255
	}
}
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
