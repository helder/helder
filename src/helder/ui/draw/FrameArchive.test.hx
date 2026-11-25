package helder.ui.draw;

import haxe.io.Bytes;
import helder.gfx.shader.Vec4;
import helder.gfx.Device;
import helder.gfx.PassDesc;
import helder.image.Image;
import helder.image.PngEncoder;
import helder.os.Surface;
import helder.test.Test;
import helder.ui.*;
import helder.view.Render;

// A frame written as data (FrameWriter), stored (FrameArchive) and read
// back (FrameReader) draws what painting the screen drew: each story below
// drawn live and replayed from the decoded file, at 2x, pixel for pixel
function tests() {
	describe("FrameArchive", () -> {
		test("floats: on the grid as steps, else raw", () -> {
			var o = new FrameStreams(), values = [0, 12.5, 12.5, -3.25, 1 / 3, 1e300, Math.NaN, 1 / 64];
			for (v in values)
				o.float(1, v);
			var r = new FrameStreams.FrameInput(o.bytes()), back = [for (_ in values) r.float(1)];
			equals(back.slice(0, 6), values.slice(0, 6));
			assert(Math.isNaN(back[6]));
			equals(back[7], 1 / 64);
		});
		test("a screen's name, key and size kept; another version's file none", () -> {
			var a = new FrameArchive(), w = new FrameWriter();
			w.rect(1, 2, 3, 4, 0, 0xFF102030, 0, 0);
			a.add("one", "k1", 390, 844, w.frame());
			var b = FrameArchive.decode(a.encode());
			equals({names: b.names(), key: b.key("one"), size: b.size("one")}, {names: ["one"], key: "k1", size: {width: 390.0, height: 844.0}});
			var bytes = a.encode();
			bytes.set(4, 99);
			equals(FrameArchive.decode(bytes), null);
		});
		test("a pass's box read back as a placeholder", () -> {
			var w = new FrameWriter(), a = new FrameArchive();
			w.gpuTexture(cast 0, 1, 10, 20, 200, 100);
			a.add("scene", "k", 220, 120, w.frame());
			var again = new FrameWriter(), placeholder = new FrameWriter();
			FrameArchive.decode(a.encode()).list("scene").replay(again);
			placeholder.rect(10, 20, 200, 100, 0, GpuPlaceholder.COLOR, 0, 0);
			equals(again.frame().bytes.toHex(), placeholder.frame().bytes.toHex());
			// (drawn by a node on a writer: its box, the writer told)
			var w = new FrameWriter();
			GpuPlaceholder.draw(w, 10, 20, 200, 100);
			equals(w.passes, 1);
		});
		test("a loop's frames as steps from the last: kept ops' numbers, come and gone ops whole", () -> {
			var frames = [], w = new FrameWriter();
			w.rect(0, 0, 10, 10, 0, 0xFF000000, 0, 0);
			w.loop(30);
			for (f in 0...70) {
				if (f > 0) w.next();
				w.rect(0, 0, 100, 100, 0, 0xFFFFFFFF, 0, 0);
				if (f % 7 < 3) w.rect(5, 5, 20, 20, 4, 0xFF00FF00, 0, 0);
				w.pushOpacity(f / 70);
				w.rect(f * 1.5, 40 + 1 / 3, 10, 10, 2, 0xFFFF0000, 0, 0);
				w.popOpacity();
				w.rect(90, 90, 5, 5, 0, 0xFF0000FF, 0, 0);
				frames.push(f);
			}
			var a = new FrameArchive();
			a.add("l", "k", 100, 100, w.frame());
			var b = FrameArchive.decode(a.encode()), l = b.loop("l");
			equals({fps: l.fps, n: l.lists.length}, {fps: 30, n: 70});
			// (each frame read back is the frame painted)
			for (f in frames) {
				var want = new FrameWriter(), got = new FrameWriter();
				want.rect(0, 0, 100, 100, 0, 0xFFFFFFFF, 0, 0);
				if (f % 7 < 3) want.rect(5, 5, 20, 20, 4, 0xFF00FF00, 0, 0);
				want.pushOpacity(f / 70);
				want.rect(f * 1.5, 40 + 1 / 3, 10, 10, 2, 0xFFFF0000, 0, 0);
				want.popOpacity();
				want.rect(90, 90, 5, 5, 0, 0xFF0000FF, 0, 0);
				l.lists[f].replay(got);
				equals(got.frame().bytes.toHex(), want.frame().bytes.toHex());
			}
		});
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		final stories:Array<{name:String, w:Int, h:Int, mount:Node->(() -> Void)}> = [
			{name: "todo", w: 390, h: 520, mount: root -> Render.render(Fixture.todo(), root)},
			{name: "text", w: 420, h: 520, mount: root -> Render.render(Fixture.text(), root)},
			{name: "gradients", w: 360, h: 300, mount: root -> Render.render(Fixture.gradients(), root)},
			{name: "paths", w: 300, h: 200, mount: root -> {
				root.append(new Shapes());
				() -> {};
			}},
			{name: "svg", w: 300, h: 120, mount: root -> Render.render(Fixture.icons(), root)},
			{name: "images", w: 300, h: 160, mount: root -> Render.render(Fixture.images(), root)},
			{name: "layers", w: 360, h: 300, mount: root -> Render.render(Fixture.layers(), root)},
			{name: "shadows", w: 360, h: 260, mount: root -> Render.render(Fixture.shadows(), root)},
			// (a font of no file, an app's own: stored in the file)
			{name: "own font", w: 300, h: 80, mount: root -> {
				helder.text.SystemFonts.get().add(helder.asset.Asset.embed("helder/text/fonts/Inter.ttf"));
				Render.render(Fixture.own(), root);
			}}
		];
		test("a loop replayed as drawn, frame by frame", () -> {
			var g = new Golden(320, 200), t = helder.view.graph.Graph.signal(0);
			var dispose = Render.render(Fixture.moving(t), g.ui.root);
			g.ui.update();
			var w = new FrameWriter();
			g.ui.paint(w);
			w.loop(30);
			var lives = [];
			for (f in 0...64) {
				if (f > 0) w.next();
				t(f);
				helder.view.graph.Graph.flush();
				g.ui.update();
				g.ui.paint(w);
				if (f % 9 == 0) lives.push({f: f, px: g.live()});
			}
			var a = new FrameArchive();
			a.add("moving", "k", 320, 200, w.frame());
			var l = FrameArchive.decode(a.encode()).loop("moving");
			equals(l.lists.length, 64);
			var off = [for (s in lives) differ(s.px, g.replay(l.lists[s.f]))];
			dispose();
			g.dispose();
			equals(off, [for (_ in lives) 0]);
		});
		for (s in stories)
			test("replayed as drawn: " + s.name, () -> {
				var g = new Golden(s.w, s.h);
				var dispose = s.mount(g.ui.root);
				g.ui.update();
				var live = g.live(), writer = new FrameWriter();
				g.ui.paint(writer);
				var a = new FrameArchive();
				a.add(s.name, "key", s.w, s.h, writer.frame());
				var file = a.encode(), list = FrameArchive.decode(file).list(s.name);
				notEquals(list, null);
				var replay = g.replay(list);
				// (the CPU's canvas: the same)
				function soft(draw:helder.ui.draw.soft.SoftCanvas->Void):Bytes {
					var c = new helder.ui.draw.soft.SoftCanvas();
					c.scale = 2;
					c.begin(s.w * 2, s.h * 2, 0xFFFFFFFF);
					draw(c);
					return c.frame.pixels.sub(0, s.w * s.h * 16);
				}
				var softLive = soft(c -> g.ui.paint(c)), softReplay = soft(c -> list.replay(c));
				dispose();
				g.dispose();
				// (written again from what was read: the same frame)
				var again = new FrameWriter();
				list.replay(again);
				equals(again.frame().bytes.toHex(), writer.frame().bytes.toHex());
				// (something drawn: not a blank screen's)
				var blank = Bytes.alloc(live.length);
				blank.fill(0, live.length, 255);
				assert(differ(live, blank) > 1000);
				assert(differ(softLive, blank) > 1000);
				equals(differ(live, replay), 0);
				equals(differ(softLive, softReplay), 0);
			});
		#end
	});
}

// (the pixels that differ)
function differ(a:Bytes, b:Bytes):Int {
	var n = 0;
	for (i in 0...a.length >> 2)
		if (a.getInt32(i * 4) != b.getInt32(i * 4)) n++;
	return n;
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (a screen at 2x: drawn by a headless device's renderer, read back)
private class Golden {
	static final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};

	public final ui:Ui;
	final w:Int;
	final h:Int;
	final device:Device;
	final r:Renderer;

	public function new(w:Int, h:Int) {
		this.w = w;
		this.h = h;
		ui = new Ui(new DrawText(), w, h);
		device = Device.create(Surface.headless(w * 2, h * 2));
		r = new Renderer(device);
		r.scale = ui.scale = 2;
		r.background = 0xFFFFFFFF;
	}

	public function live():Bytes
		return frame(() -> ui.paint(r));

	public function replay(list:DisplayList):Bytes
		return frame(() -> list.replay(r));

	function frame(draw:() -> Void):Bytes {
		var enc = device.beginFrame();
		r.begin(w * 2, h * 2);
		draw();
		r.prepare(enc);
		enc.beginPass(pass);
		r.end(enc);
		enc.endPass();
		// (read before the frame ends: after, the surface's is gone)
		var b = Bytes.alloc(w * h * 16);
		device.readPixels(b);
		device.endFrame();
		return b;
	}

	public function dispose()
		device.dispose();
}

// (a node drawing paths of its own: strokes, fills, dashes, a curve)
private class Shapes extends Node {
	public function new() {
		super();
		style.set({width: 280, height: 180});
	}

	override public function hasContent():Bool
		return true;

	override public function paintContent(c:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var p = new Path();
		p.moveTo(x + 10, y + 10);
		p.lineTo(x + 90, y + 30);
		p.lineTo(x + 30, y + 80);
		p.close();
		c.path(p, 0xFF3B82F6, {width: 3, paint: 0xFF1E3A8A, join: Round});
		var q = new Path();
		q.moveTo(x + 110, y + 90);
		q.cubicTo(x + 140, y + 10, x + 200, y + 170, x + 260, y + 40);
		c.path(q, null, {width: 2.5, paint: 0xFFEF4444, cap: Round, dashes: [8, 5], dashOffset: 2});
		var r = new Path();
		r.moveTo(x + 20, y + 110);
		r.lineTo(x + 120, y + 110);
		r.lineTo(x + 120, y + 170);
		r.lineTo(x + 20, y + 170);
		r.close();
		r.moveTo(x + 45, y + 125);
		r.lineTo(x + 95, y + 125);
		r.lineTo(x + 95, y + 155);
		r.lineTo(x + 45, y + 155);
		r.close();
		r.evenOdd = true;
		c.path(r, Gradient.parse("linear-gradient(90deg, #f59e0b, #10b981)"), {width: 1, paint: 0xFF111827, cap: Square, join: Bevel, miterLimit: 2});
	}
}

private class Fixture implements helder.view.Markup {
	public static function todo()
		return <view width={390} height={520} background="#f8fafc" padding={20} gap={12}>
			<text font-size={28} font-weight={700} color="#0f172a">Today</text>
			<view direction="row" gap={8}>
				<view grow={1} height={40} radius={10} background="#ffffff" border-width={1} border-color="#e2e8f0" padding="0 12" justify="center">
					<text color="#94a3b8">What needs doing?</text>
				</view>
				<view width={72} height={40} radius={10} background="#2563eb" align-items="center" justify="center">
					<text color="#ffffff" font-weight={600}>Add</text>
				</view>
			</view>
			{[for (i => t in ["Buy oat milk", "Water the ferns", "Call the plumber about the leaking tap in the upstairs bathroom", "Book train tickets", "Reply to Ada"]) row(t, i % 2 == 1)]}
			<text color="#64748b" font-size={13}>3 of 5 left</text>
		</view>;

	static function row(t:String, done:Bool)
		return <view direction="row" gap={10} align-items="center" padding="10 12" radius={12} background="#ffffff" shadow="0 1 3 #0000001a">
			<view width={20} height={20} radius={6} border-width={2} border-color={done ? "#16a34a" : "#cbd5e1"} background={done ? "#16a34a" : "#ffffff"}/>
			<text grow={1} shrink={1} color={done ? "#94a3b8" : "#0f172a"} text-decoration={done ? "line-through" : "none"}>{t}</text>
		</view>;

	public static function text()
		return <view width={420} padding={16} gap={10} background="#ffffff">
			<text font-size={22} font-weight={700}>A heading, then paragraphs</text>
			<text line-height={1.5} color="#334155">Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</text>
			<text italic text-align="center" color="#7c3aed" font-size={15}>Centred, italic: the quick brown fox jumps over the lazy dog</text>
			<text text-align="right" font-weight={300} letter-spacing={1.5}>Right, light, spaced</text>
			<text font-size={11} color="#475569">{"Small print: 0123456789 ÀÉÎÕÜ ñ ß æ ø — “quotes” …"}</text>
			<text font-size={40} font-weight={800} color="#0f172a">Big 48px</text>
			<text font-family="monospace" font-size={13}>let x = frames.map(f => f.key)</text>
			<text text-shadow="0 2 4 #00000066" font-size={20} color="#ffffff" background="#1e293b" padding={8}>A text shadow</text>
			<text text-decoration="underline" color="#2563eb">An underlined link</text>
		</view>;

	public static function gradients()
		return <view width={360} padding={12} gap={12} direction="row" wrap="wrap">
			<view width={100} height={80} radius={12} background="linear-gradient(135deg, #6366f1, #ec4899)"/>
			<view width={100} height={80} radius={40} background="radial-gradient(circle at 30% 30%, #fde68a, #f97316 60%, #7c2d12)"/>
			<view width={100} height={80} background="repeating-linear-gradient(45deg, #e2e8f0 0 10px, #94a3b8 10px 20px)"/>
			<view width={100} height={80} radius={8} background="linear-gradient(to bottom, #00000000, #000000aa)"/>
			<view width={220} height={80} radius={16} background="radial-gradient(ellipse farthest-corner, #22d3ee, #1e40af)"/>
		</view>;

	public static function icons()
		return <view direction="row" gap={12} padding={12} align-items="center">
			<svg viewBox="0 0 24 24" width={24} height={24}><path d="M12 2l3 7h7l-5.5 4 2 7-6.5-4.5L5.5 20l2-7L2 9h7z" fill="#f59e0b"/></svg>
			<svg viewBox="0 0 24 24" width={40} height={40}><circle cx="12" cy="12" r="9" fill="none" stroke="#0ea5e9" stroke-width="2"/><path d="M8 12l3 3 5-6" fill="none" stroke="#0ea5e9" stroke-width="2" stroke-linecap="round"/></svg>
			<svg viewBox="0 0 10 10" width={64} height={64}><defs><linearGradient id="g"><stop offset="0" stop-color="#10b981"/><stop offset="1" stop-color="#3b82f6"/></linearGradient></defs><rect x="1" y="1" width="8" height="8" rx="2" fill="url(#g)"/></svg>
			<svg viewBox="0 0 16 16" width={20} height={20} color="#ef4444"><path d="M8 1v14M1 8h14" stroke="currentColor" stroke-width="2"/></svg>
		</view>;

	public static function images()
		return <view direction="row" gap={12} padding={12}>
			<image src={Pictures.pixels()} width={96} height={96}/>
			<image src={Pictures.file()} width={120} height={80} radius={16}/>
			<image src={Pictures.file()} width={40} height={40} radius={20}/>
		</view>;

	public static function layers()
		return <view width={360} height={300} padding={16} gap={12}>
			<view width={200} height={70} radius={20} overflow="hidden" background="#e0e7ff">
				<view width={260} height={30} background="#4f46e5" transform="translate(-20px, 20px) rotate(-8deg)"/>
				<text color="#1e1b4b">clipped and turned</text>
			</view>
			<view direction="row" gap={12}>
				<view width={80} height={80} background="#ef4444" opacity={0.5}/>
				<view width={80} height={80} background="#22c55e" opacity={0.7} radius={8} transform="scale(0.8) rotate(12deg)">
					<view width={40} height={40} background="#14532d" opacity={0.5}/>
				</view>
				<view width={80} height={80} radius={40} overflow="hidden" background="#fde047">
					<text font-size={30} font-weight={700}>Oo</text>
				</view>
			</view>
			<view width={300} height={60} border-width={2} border-style="dashed" border-color="#64748b" radius={12} padding={8}>
				<text>dashed border</text>
			</view>
			<view width={300} height={30} border-width="0 0 4 0" border-color="#0ea5e9" background="#f1f5f9"/>
		</view>;

	// (a box moving, a counter, a badge that comes and goes, a bar filling)
	public static function moving(t:helder.view.graph.Signal<Int>)
		return <view width={320} height={200} padding={16} gap={10} background="#0f172a">
			<view width={40} height={40} radius={8} background="#38bdf8" transform={'translate(${t() * 3.5}px, 0px)'}/>
			<text color="#ffffff" font-size={18}>{"Score " + Std.int(t() / 8)}</text>
			{t() % 20 < 8 ? <view width={60} height={20} radius={10} background="#f59e0b"/> : null}
			<view width={280} height={8} radius={4} background="#1e293b"><view width={t() * 4.25} height={8} radius={4} background="#22c55e"/></view>
		</view>;

	public static function own()
		return <view padding={12}><text font-family="Inter" font-size={24} font-weight={600}>Inter, stored</text></view>;

	public static function shadows()
		return <view width={360} height={260} padding={24} gap={24} direction="row" wrap="wrap" background="#f1f5f9">
			<view width={90} height={90} radius={12} background="#ffffff" shadow="0 10 25 #0000002e"/>
			<view width={90} height={90} radius={45} background="#ffffff" shadow="0 0 0 4 #3b82f6, 0 8 16 #1e3a8a66"/>
			<view width={90} height={90} radius={12} background="#e2e8f0" shadow="inset 0 2 6 #00000055"/>
			<view width={140} height={60} radius="4 20 4 20" background="#fef3c7" shadow="6 6 0 #92400e"/>
		</view>;
}

// (an image of pixels made here, and one decoded from a file)
private class Pictures {
	static var made:Null<Image>;
	static var decoded:Null<Image>;

	public static function pixels():Image {
		if (made != null) return made;
		var img = new Image(48, 48);
		for (y in 0...48)
			for (x in 0...48)
				img.pixels.setInt32((y * 48 + x) * 4, 0xFF000000 | (x * 5) << 16 | (y * 5) << 8 | ((x ^ y) * 4 & 0xFF));
		return made = img;
	}

	public static function file():Image {
		if (decoded != null) return decoded;
		var px = Bytes.alloc(60 * 40 * 4);
		for (i in 0...60 * 40)
			px.setInt32(i * 4, (i * 40503 * 7919) | 0xFF000000);
		return decoded = Image.decode(PngEncoder.encode(px, 60, 40));
	}
}
#end
