import helder.gfx.Color;
import haxe.io.Bytes;
import helder.ui.*;
import helder.ui.draw.*;
import sys.io.File;

// Every kind of <glass> (as the glass demo's: regular, clear, four tints,
// four shapes, a group of four) over fixed bands (two gradients, stripes,
// text), drawn by helder's shader and compared with the system's own on
// screen (macOS 26's NSGlassEffectView: tests/ui/glass-kinds.swift shows
// it over this scene's bands, drawn by helder, and captures its window):
// per kind the mean difference over its box and its rim, both side by side.
//   GlassKindsCheck --background dir [scale]: dir/bands.png, dir/kinds.txt (the
//   glass, as the reference tool takes it)
//   GlassKindsCheck --compare ref.png outdir [scale] [inactive]: against the
//   system's capture, outdir/side.png, outdir/<kind>.png, the numbers printed
//   GlassKindsCheck --tune ref.png scale regular|clear i,j,... kind,kind [inactive]:
//   GlassPass's look searched, one parameter at a time, nearest the
//   capture over those kinds
class GlassKindsCheck {
	public static inline var W = 480;
	public static inline var H = 330;

	static function main() {
		var a = Sys.args();
		// (the scale: --background's third argument, --tune's second, --compare's third)
		var at = a[0] == "--compare" ? 3 : 2, k = a.length > at && Std.parseFloat(a[at]) > 0 ? Std.parseFloat(a[at]) : 2;
		if (a[0] == "--background") return background(a[1], k);
		if (a[0] == "--compare") return compare(a[1], a[2], k, a.indexOf("inactive") >= 0);
		if (a[0] == "--tune") return tune(a[1], k, a[3] == "clear" ? (a.indexOf("inactive") >= 0 ? GlassPass.clearInactive : GlassPass.clear) : (a.indexOf("inactive") >= 0 ? GlassPass.regularInactive : GlassPass.regular), [for (v in a[4].split(",")) Std.parseInt(v)], a[5].split(","),
			a.indexOf("inactive") >= 0);
	}

	// the bands, and (glass) the kinds over them: each kind's name and node
	public static function build(root:Node, glass = true):Array<{name:String, node:Node}> {
		helder.text.SystemFonts.get().add(helder.asset.Embed.bytes("helder/text/fonts/Inter.ttf"));
		root.style.set({width: W, height: H, background: 0xFFFFFFFF, fontFamily: "Inter"});
		function band(top:Float, h:Float):Node {
			var b = new Node();
			b.style.set({position: Absolute, left: 0, top: top, width: W, height: h, overflow: Hidden});
			root.append(b);
			return b;
		}
		band(0, 90).style.backgroundImage = Gradient.parse("linear-gradient(135deg, #ff5e62, #ff9966)");
		var stripes = band(90, 70);
		stripes.style.flexDirection = Row;
		for (i in 0...Std.int(W / 10)) {
			var s = new Node();
			s.style.set({width: 10, height: 70, background: i % 2 == 0 ? 0xFF111111 : 0xFFFAFAFA});
			stripes.append(s);
		}
		var text = band(160, 90);
		text.style.set({padding: 8, rowGap: 1});
		for (i in 0...4) {
			var t = new TextNode("The quick brown fox jumps over the lazy dog. Text behind glass shows the blur and the lens.");
			t.style.set({fontSize: 13, color: 0xFF18181B});
			text.append(t);
		}
		band(250, 80).style.backgroundImage = Gradient.parse("linear-gradient(135deg, #36d1dc, #5b86e5)");
		if (!glass) return [];
		var out = [];
		function add(name:String, x:Float, y:Float, w:Float, h:Float, ?set:Glass->Void) {
			var g = new Glass();
			g.style.set({position: Absolute, left: x, top: y, width: w, height: h});
			if (set != null) set(g);
			root.append(g);
			out.push({name: name, node: (g : Node)});
		}
		add("regular", 16, 64, 120, 56);
		add("clear", 146, 64, 120, 56, g -> g.variant = "clear");
		add("blue", 276, 68, 92, 48, g -> g.tint = Color.parse("#0a84ff55"));
		add("red", 378, 68, 92, 48, g -> g.tint = Color.parse("#ff375f66"));
		add("green", 16, 136, 92, 48, g -> g.tint = Color.parse("#30d15888"));
		add("dark", 118, 136, 92, 48, g -> g.tint = Color.parse("#000000aa"));
		add("capsule", 220, 136, 110, 48);
		add("radius16", 340, 132, 110, 64, g -> g.style.borderRadius = 16);
		add("radius4", 16, 222, 90, 64, g -> g.style.borderRadius = 4);
		add("circle", 116, 222, 64, 64);
		var group = new Node();
		GlassGroup.of(group, 16);
		group.style.set({position: Absolute, left: 196, top: 228, flexDirection: Row, columnGap: 4});
		for (_ in 0...4) {
			var c = new Glass();
			c.style.set({width: 52, height: 52});
			group.append(c);
		}
		root.append(group);
		out.push({name: "group", node: (group : Node)});
		return out;
	}

	// (the scene laid out at scale k: its pixels drawn, its kinds)
	static function draw(f:DrawFrame, k:Float, glass:Bool, active:Bool):{pixels:Bytes, kinds:Array<{name:String, node:Node}>} {
		var ui = new Ui(helder.ui.TextEngines.standard(), W, H);
		var kinds = build(ui.root, glass);
		for (g in glassOf(kinds))
			g.active = active;
		f.scale = k;
		ui.update();
		return {pixels: f.draw(ui), kinds: kinds};
	}

	static function glassOf(kinds:Array<{name:String, node:Node}>):Array<Glass> {
		var out = [];
		for (k in kinds)
			if (Std.isOfType(k.node, Glass)) out.push((cast k.node : Glass)) else for (c in k.node.children)
				out.push(cast c);
		return out;
	}

	static function background(dir:String, k:Float) {
		var w = Math.round(W * k), h = Math.round(H * k), f = new DrawFrame(w, h);
		File.saveBytes('$dir/bands.png', Png.encode(draw(f, k, false, true).pixels, w, h));
		f.dispose();
		// (each glass: kind x y w h radius style tint; a group: group x y w h spacing, then its glass)
		var ui = new Ui(helder.ui.TextEngines.standard(), W, H), lines = [];
		var kinds = build(ui.root);
		ui.update();
		for (kd in kinds) {
			var n = kd.node;
			if (n.glassSpacing != null) {
				lines.push('group ${n.absX} ${n.absY} ${n.width} ${n.height} ${n.glassSpacing}');
				for (c in n.children)
					lines.push(line("child", cast c));
			} else lines.push(line(kd.name, cast n));
		}
		File.saveContent('$dir/kinds.txt', lines.join("\n") + "\n");
	}

	static function line(name:String, g:Glass):String {
		var t = g.tint;
		return '$name ${g.absX} ${g.absY} ${g.width} ${g.height} ${g.radius()} ${g.clear ? 1 : 0} '
			+ (t == null ? "-" : "#" + StringTools.hex(t & 0xFFFFFF, 6) + StringTools.hex(t.a, 2));
	}

	static function tune(ref:String, k:Float, look:Array<Float>, which:Array<Int>, names:Array<String>, inactive:Bool) {
		var w = Math.round(W * k), h = Math.round(H * k), f = new DrawFrame(w, h), want = helder.image.PngDecoder.decode(File.getBytes(ref)).rgba;
		// (one tree drawn again at each step: the look is GlassPass's, read as it draws)
		var ui = new Ui(helder.ui.TextEngines.standard(), W, H), kinds = build(ui.root);
		for (g in glassOf(kinds))
			g.active = !inactive;
		f.scale = k;
		ui.update();
		function loss():Float {
			ui.requestFrame();
			// (over 4x4 blocks' means: what shows through, not where an edge falls within a pixel)
			var d = {pixels: f.draw(ui), kinds: kinds}, sum = 0.0, cnt = 0, m = Math.round(6 * k), B = 4;
			for (kd in d.kinds) {
				if (names.indexOf(kd.name) < 0) continue;
				var n = kd.node, bx0 = Std.int(Math.max(0, Math.round(n.absX * k) - m) / B), by0 = Std.int(Math.max(0, Math.round(n.absY * k) - m) / B);
				var bx1 = Std.int(Math.min(w, Math.round((n.absX + n.width) * k) + m) / B), by1 = Std.int(Math.min(h, Math.round((n.absY + n.height) * k) + m) / B);
				for (by in by0...by1)
					for (bx in bx0...bx1)
						for (c in 0...3) {
							var a = 0.0, b = 0.0;
							for (j in 0...B)
								for (i in 0...B) {
									var o = ((by * B + j) * w + bx * B + i) * 4 + c;
									a += d.pixels.get(o);
									b += want.get(o);
								}
							sum += Math.abs(a - b) / (B * B);
							cnt++;
						}
			}
			return sum / cnt;
		}
		var best = loss();
		for (round in 0...4)
			for (j in which) {
				var st = Math.max(Math.abs(look[j]) * 0.3, 0.05) / (1 << round), moved = true;
				while (moved) {
					moved = false;
					for (dir in [-1, 1]) {
						var was = look[j];
						look[j] = Math.max(0, was + dir * st);
						var l = loss();
						if (l < best - 0.001) {
							best = l;
							moved = true;
							break;
						}
						look[j] = was;
					}
				}
			}
		f.dispose();
		Sys.println('GlassKindsCheck: ${[for (x in look) Math.round(x * 1000) / 1000]}, ${Math.round(best * 100) / 100} levels');
	}

	static function compare(ref:String, outDir:String, k:Float, inactive:Bool) {
		var w = Math.round(W * k), h = Math.round(H * k), f = new DrawFrame(w, h);
		var d = draw(f, k, true, !inactive), want = helder.image.PngDecoder.decode(File.getBytes(ref));
		f.dispose();
		if (want.width != w || want.height != h) throw 'GlassKindsCheck: $ref is ${want.width}x${want.height}, not ${w}x$h';
		var m = Math.round(6 * k), total = 0.0, line = [];
		for (kd in d.kinds) {
			var n = kd.node, x0 = Std.int(Math.max(0, Math.round(n.absX * k) - m)), y0 = Std.int(Math.max(0, Math.round(n.absY * k) - m));
			var x1 = Std.int(Math.min(w, Math.round((n.absX + n.width) * k) + m)), y1 = Std.int(Math.min(h, Math.round((n.absY + n.height) * k) + m));
			var sum = 0.0, cnt = 0, cw = x1 - x0, ch = y1 - y0, crop = Bytes.alloc(cw * ch * 8);
			for (y in y0...y1)
				for (x in x0...x1) {
					var o = (y * w + x) * 4;
					for (c in 0...3)
						sum += Math.abs(d.pixels.get(o + c) - want.rgba.get(o + c));
					cnt += 3;
					var p = ((y - y0) * cw * 2 + (x - x0)) * 4;
					crop.setInt32(p, want.rgba.getInt32(o) | 0xFF000000);
					crop.setInt32(p + cw * 4, d.pixels.getInt32(o) | 0xFF000000);
				}
			File.saveBytes('$outDir/${kd.name}.png', Png.encode(crop, cw * 2, ch));
			total += sum / cnt;
			line.push('${kd.name} ${Math.round(sum / cnt * 10) / 10}');
		}
		var side = Bytes.alloc(w * h * 8);
		for (y in 0...h) {
			side.blit(y * w * 8, want.rgba, y * w * 4, w * 4);
			side.blit(y * w * 8 + w * 4, d.pixels, y * w * 4, w * 4);
		}
		File.saveBytes('$outDir/side.png', Png.encode(side, w * 2, h));
		Sys.println('GlassKindsCheck (${inactive ? "inactive" : "active"}): ${line.join(", ")}; mean ${Math.round(total / d.kinds.length * 10) / 10} levels');
	}
}
