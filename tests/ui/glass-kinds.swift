// The system's Liquid Glass on screen over GlassKinds' bands (macOS 26):
// NSGlassEffectView for each kind, a group's in an
// NSGlassEffectContainerView, in a borderless window kept behind every
// other (never activated, never key: the system's glass as in a window that
// is not the key one), the window captured by the window server
// (screencapture -l: Screen Recording's permission), in sRGB.
//   swiftc -O tests/ui/glass-kinds.swift -o bin/glass-kinds
//   glass-kinds <bands.png> <kinds.txt> <scale> <out.png>
import AppKit

let a = CommandLine.arguments
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .aqua)
class Behind: NSWindow {
	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}
let bg = NSImage(contentsOfFile: a[1])!
let k = Double(a[3])!
let rep = bg.representations[0]
let W = Double(rep.pixelsWide) / k, H = Double(rep.pixelsHigh) / k
let win = Behind(contentRect: NSRect(x: 120, y: 120, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
win.appearance = app.appearance
win.hasShadow = false
let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
root.wantsLayer = true
let back = CALayer()
back.frame = root.bounds
back.contents = bg.cgImage(forProposedRect: nil, context: nil, hints: nil)
back.contentsScale = k
root.layer!.addSublayer(back)

func glass(_ f: [String], in parent: NSView, height: Double, dx: Double, dy: Double) {
	let x = Double(f[1])! - dx, y = Double(f[2])! - dy, w = Double(f[3])!, h = Double(f[4])!
	let v = NSGlassEffectView(frame: NSRect(x: x, y: height - y - h, width: w, height: h))
	v.cornerRadius = Double(f[5])!
	v.style = f[6] == "1" ? .clear : .regular
	if f[7] != "-" {
		let t = UInt32(f[7].dropFirst(), radix: 16)!
		v.tintColor = NSColor(srgbRed: Double(t >> 24 & 0xFF) / 255, green: Double(t >> 16 & 0xFF) / 255, blue: Double(t >> 8 & 0xFF) / 255, alpha: Double(t & 0xFF) / 255)
	}
	parent.addSubview(v)
}

var group: (NSView, Double, Double, Double)? = nil
for l in try! String(contentsOfFile: a[2], encoding: .utf8).split(separator: "\n") {
	let f = l.split(separator: " ").map(String.init)
	if f[0] == "group" {
		let x = Double(f[1])!, y = Double(f[2])!, w = Double(f[3])!, h = Double(f[4])!
		let c = NSGlassEffectContainerView(frame: NSRect(x: x, y: H - y - h, width: w, height: h))
		c.spacing = Double(f[5])!
		let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
		c.contentView = content
		root.addSubview(c)
		group = (content, x, y, h)
	} else if f[0] == "child", let g = group {
		glass(f, in: g.0, height: g.3, dx: g.1, dy: g.2)
	} else {
		glass(f, in: root, height: H, dx: 0, dy: 0)
	}
}
win.contentView = root
// (behind every window: shown, never in front of anyone's)
win.order(.below, relativeTo: 0)
RunLoop.main.run(until: Date().addingTimeInterval(1.0))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l\(win.windowNumber)", a[4]]
try! p.run()
p.waitUntilExit()
// (the display's colours (Display P3) back to sRGB, as the bands were drawn)
let shot = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[4])))!
try! shot.converting(to: .sRGB, renderingIntent: .default)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[4]))
