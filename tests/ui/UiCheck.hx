import helder.os.Edges;
import helder.os.Mods;
import helder.gfx.Color;
import helder.ui.*;
import helder.ui.platform.*;
import helder.ui.DimValue;
import helder.ui.actions.Keymap;
import helder.ui.actions.Keystroke;
import helder.ui.controls.TextField;
import helder.ui.controls.TextArea;
import helder.ui.controls.EditableText;
import helder.ui.controls.EditableText.SpellAction;
import helder.image.Image;
import helder.image.PngDecoder;

// helder.ui's tests, on Eval (bun run test ui):
//
//   <tool> -cp src -cp tests/ui --run UiCheck
//
// - layout: layout-cases.json laid out by Layout against Chromium's
//   flexbox (layout-expected.json, from layout-ref.mjs), every box exact
// - text: TextNode measured and wrapped by MonoText
// - events: hit testing, hover, press and click, bubbling, focus and Tab,
//   the wheel scrolling an Overflow Scroll node, relayout after changes
// - paint: what Ui draws on a Canvas, in order (shadows under backgrounds,
//   rounded clips inside borders), and Shadow.parse
// - fields: TextField's editing (words, undo and redo, double and triple
//   clicks, Shift+click) and the clipboard (copy, cut, paste), an
//   input method's composition (shown, then committed);
//   TextArea's lines (wrapping, Enter, Up and Down, Home and End, scrolling)
// - popups: placed by their anchors (flipped, kept in the window), drawn
//   and hit over the tree, dismissed by outside presses and Escape, a
//   modal one keeping the focus
// - images: ImageNode's size and placement (fit, object-position); the
//   decoders are helder.image's, tested by tests/image
class UiCheck {
	static var checks = 0;
	static var failed = 0;

	static function main() {
		var here = haxe.io.Path.directory(haxe.macro.Compiler.getDefine("UiCheck") ?? Sys.programPath() ?? "tests/ui/UiCheck.hx");
		if (!sys.FileSystem.exists(here + "/layout-cases.json")) here = "tests/ui";
		layouts(here);
		texts();
		events();
		dirty();
		paint();
		groups();
		themes();
		transitions();
		images();
		svgs(here);
		svgApi();
		css(here);
		decorations();
		transforms();
		paths();
		calcs();
		sticky();
		stacking();
		visibility();
		pointerEvents();
		rtlScroll();
		scrollSet();
		nativeScrolls();
		trackpad();
		overlayBars();
		androidScroll();
		noWrap();
		textTransform();
		culling();
		inPlace();
		replayed();
		restyled();
		editing();
		selection();
		fields();
		popups();
		shortcuts();
		natives();
		keyboards();
		noFont();
		// (last: it turns motion on, for good)
		layered();
		layerRecords();
		#if !helder.layout
		// (on the CSS engine's layout, NodeBoxes: what it does not do yet, fewer as the port goes on)
		Sys.println('UiCheck: $checks checks, $failed failed on the engine, at most 3');
		if (failed < 3) Sys.println('UiCheck: lower the engine\'s failures to $failed');
		Sys.exit(failed <= 3 ? 0 : 1);
		#else
		Sys.println('UiCheck: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
		#end
	}

	// a field's keyboard (TextKind): its defaults by kind, Enter's next and
	// done after onSubmit, a native editor told its kind and selection, the
	// focused field kept above the soft keyboard (Ui.keyboard)
	static function keyboards() {
		var k = new helder.os.TextKind(Email);
		check("keyboards: an email's not capitalised nor corrected", k.capitalize == None && !k.autocorrect);
		k = new helder.os.TextKind();
		check("keyboards: text's sentences, corrected", k.capitalize == Sentences && k.autocorrect);
		check("keyboards: a password's not corrected", !new helder.os.TextKind(Text, Default, null, null, true).autocorrect);
		var ui = new Ui(new MonoText(), 300, 200);
		var a = new TextField(""), b = new TextField(""), c = new TextField("");
		var submitted = [];
		for (f in [a, b, c]) {
			f.style.set({width: 100, height: 20});
			f.onSubmit = t -> submitted.push(f == a ? "a" : f == b ? "b" : "c");
			ui.root.append(f);
		}
		a.enterkey = Next;
		b.enterkey = Done;
		c.keyboard = Number;
		ui.update();
		ui.setFocus(a);
		check("keyboards: the focus's kind", ui.textKind().enter == Next && ui.textKind().keyboard == Text);
		ui.keyDown(Key.ENTER, 0);
		check("keyboards: next: submitted, the focus on the next field", ui.focus == b && submitted.join(",") == "a");
		ui.keyDown(Key.ENTER, 0);
		check("keyboards: done: submitted, no focus", ui.focus == null && submitted.join(",") == "a,b");
		check("keyboards: no focus, no kind", ui.textKind() == null);
		var views = new FakeViews();
		ui.platform = views;
		ui.update();
		var ec = views.made[2];
		check("keyboards: a native editor told its kind", ec.kind != null && ec.kind.keyboard == Number);
		c.setText("12345");
		ui.update();
		c.select(1, 3);
		ui.update();
		check("keyboards: a native editor told the program's selection", ec.text == "12345" && ec.start == 1 && ec.end == 3, '${ec.start} ${ec.end}');
		ec.listener.editorSelected(2, 4);
		check("keyboards: the editor's selection the field's", c.selectionStart == 2 && c.selectionEnd == 4);
		// (a scroller of a tall gap, a field and a footer; the keyboard up, the
		// scroller's padding the safe area's bottom, as env() gives it)
		var ui = new Ui(new MonoText(), 300, 200);
		var s = new Node("s"), gap = new Node("gap"), f = new TextField(""), foot = new Node("foot");
		s.style.set({width: 300, height: 200, overflow: Scroll});
		gap.style.set({height: 300, flexShrink: 0});
		f.style.set({width: 100, height: 20, flexShrink: 0});
		foot.style.set({height: 50, flexShrink: 0});
		s.append(gap);
		s.append(f);
		s.append(foot);
		ui.root.append(s);
		ui.update();
		ui.setFocus(f, false);
		ui.update();
		check("keyboards: no keyboard, nothing kept in view", s.scrollY == 0);
		ui.keyboard = 100;
		s.style.set({paddingBottom: 100});
		ui.update();
		var r = f.windowBounds();
		check("keyboards: the field kept above the keyboard, 16 clear", r.y + r.height == 200 - 100 - Ui.KEYBOARD_MARGIN, '${r.y + r.height}');
		ui.keyboard = 0;
		ui.update();
		ui.setFocus(null);
		ui.update();
		check("keyboards: down, the scroll left alone", s.scrollY > 0);
	}

	// no font at all (a page whose build found none to ship): the error says
	// so and what to do, and reaches App.onError's handler (helder.async.Errors)
	static function noFont() {
		var text = new helder.ui.draw.DrawText(new NoFonts());
		var got:Null<String> = null, from = "";
		var was = helder.async.Errors.handler;
		helder.async.Errors.handler = (e, source) -> {
			got = e.message;
			from = source;
			true;
		};
		helder.async.Errors.guard(() -> text.face(new helder.ui.Font("sans-serif", 14, 400, false, 1.2)), "frame");
		helder.async.Errors.handler = was;
		check("no font: an error through App.onError, its cause and its fix", from == "frame" && got != null && got.indexOf("no font to draw text with") >= 0
			&& got.indexOf("Asset.font") >= 0, '$from: $got');
	}

	// native text editors (a platform's views, faked): which host the
	// policy and the tree give, the editor over the content box, the text
	// and the focus kept in step both ways, the keys it leaves to the
	// window, drawn again while covered or clipped, gone with its node
	static function natives() {
		var ui = new Ui(new MonoText(), 300, 200);
		var f = new TextField("hi");
		f.style.set({width: 120, padding: [4, 8], borderWidth: 1});
		f.placeholder = "Name";
		var submitted = "";
		f.onSubmit = t -> submitted = t;
		var changes = 0;
		f.onChange = _ -> changes++;
		ui.root.append(f);
		ui.update();
		check("natives: no platform, drawn", ui.hostOf(f, "text-field") == Drawn);
		var views = new FakeViews();
		ui.platform = views;
		ui.update();
		var e = views.made[0];
		check("natives: the policy's text-field native", ui.hostOf(f, "text-field") == Native && views.made.length == 1 && !e.multiline);
		check("natives: over the content box", e.x == 9 && e.y == 5 && e.w == 102 && e.shown, '${e.x},${e.y} ${e.w}x${e.h} ${e.shown}');
		check("natives: its text and style", e.text == "hi" && e.placeholder == "Name");
		var rec = new Recording();
		ui.paint(rec);
		check("natives: its text not drawn", !Lambda.exists(rec.calls, c -> StringTools.startsWith(c, "text ")), rec.calls.join("|"));
		e.listener.editorEdited("hello", 5, 5);
		check("natives: typed in the editor", f.text == "hello" && f.caret == 5 && changes == 1);
		f.setText("set");
		ui.update();
		check("natives: set by the program", e.text == "set");
		ui.setFocus(f);
		ui.update();
		check("natives: the focus given", e.focused);
		e.listener.editorKey(Key.ENTER, 0);
		check("natives: Enter left to the window submits", submitted == "set");
		var b = new Node("b");
		b.focusable = true;
		b.style.set({width: 20, height: 20});
		ui.root.append(b);
		e.listener.editorKey(Key.TAB, 0);
		ui.update();
		check("natives: Tab moves the window's focus, the editor's taken back", ui.focus == b && !e.focused);
		e.listener.editorFocused(true);
		check("natives: a click in the editor focuses the field", ui.focus == f);
		var p = new Popup("dialog");
		p.style.set({width: 300, height: 200});
		ui.open(p);
		ui.update();
		check("natives: covered by a popup, drawn", !e.shown);
		ui.close(p);
		ui.update();
		check("natives: shown again", e.shown);
		f.host = Drawn;
		ui.update();
		check("natives: host Drawn: the editor gone", e.disposed);
		f.host = Auto;
		ui.root.host = Drawn;
		ui.update();
		check("natives: drawn by an ancestor's host", views.made.length == 2 && views.made[1].disposed || views.made.length == 1);
		ui.root.host = Auto;
		ui.policy["text-field"] = Host.Drawn;
		var a = new TextArea("x");
		a.host = Native;
		ui.root.append(a);
		ui.update();
		var last = views.made[views.made.length - 1];
		check("natives: host Native over the policy, a text area multiline", last.multiline && !last.disposed && ui.hostOf(f, "text-field") == Drawn);
		ui.root.remove(a);
		ui.update();
		check("natives: removed from the tree, its editor gone", last.disposed);
	}

	public static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('UiCheck: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	// --- svg ---

	// svg/*.svg drawn by Svg.render against Chromium's pixels (svg-cases.mjs):
	// compared premultiplied. Edge pixels differ by their anti-aliasing
	// (Skia's approximates; ours is the exact area, within a few levels of
	// a 16x16 supersampling of the true curves, where Skia's strokes of
	// quadratic curves are off by up to 80, its clips' edges by 25), so the
	// shapes must agree: a small mean difference, few pixels far apart.
	static function svgs(here:String) {
		var dir = here + "/svg";
		var cases:Array<{name:String, width:Int, height:Int}> = haxe.Json.parse(sys.io.File.getContent(dir + "/cases.json"));
		check("svg: the cases", cases.length >= 20, '${cases.length}');
		// (SVG_STATS=1: each case's differences; SVG_OUT=dir: our pixels into dir/<case>.rgba)
		var stats = Sys.getEnv("SVG_STATS") != null, dump = Sys.getEnv("SVG_OUT");
		for (c in cases) {
			var img = Svg.parse(sys.io.File.getContent(dir + "/" + c.name + ".svg")).render(c.width, c.height);
			if (dump != null) sys.io.File.saveBytes(dump + "/" + c.name + ".rgba", img.pixels);
			var ref = PngDecoder.decode(sys.io.File.getBytes(dir + "/" + c.name + ".png"));
			var total = 0.0, worst = 0, far = 0, a = img.pixels, b = ref.rgba;
			for (i in 0...c.width * c.height) {
				var o = i * 4, aa = a.get(o + 3), ba = b.get(o + 3), d = Std.int(Math.abs(aa - ba));
				for (k in 0...3) {
					var e = Std.int(Math.abs(a.get(o + k) * aa / 255 - b.get(o + k) * ba / 255));
					if (e > d) d = e;
				}
				total += d;
				if (d > worst) worst = d;
				if (d > 64) far++;
			}
			var mean = total / (c.width * c.height);
			if (stats) Sys.println('svg ${c.name}: mean ${Math.round(mean * 100) / 100} worst $worst far $far');
			check("svg: " + c.name + " as Chromium draws it", mean < 5 && far <= c.width * c.height / 50, 'mean $mean, worst $worst, $far pixels off by more than 64');
		}
	}

	// Svg's own behaviour, and an svg in an ImageNode
	static function svgApi() {
		var icon = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" fill="currentColor"/></svg>');
		check("svg: the viewBox's size by itself", icon.width == 24 && icon.height == 24);
		var img = icon.render(4, 4, 0xFF2563EB);
		check("svg: currentColor painted render's colour", img.pixels.get(0) == 0x25 && img.pixels.get(1) == 0x63 && img.pixels.get(2) == 0xEB && img.pixels.get(3) == 255);
		var none = 0;
		try Svg.read("<html/>") catch (_:Dynamic) none++;
		check("svg: no svg element throws", none == 1);
		var nums = Svg.SvgParse.numbers("1,2 3-4.5.5e1 -.5");
		check("svg: number lists as SVG splits them", nums.join(" ") == "1 2 3 -4.5 5 -0.5", nums.join(" "));
		var p = Svg.SvgParse.pathData("M1 1 L2 2 X 3 3");
		check("svg: path data up to an error", p.length == 6, '$p');
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.alignItems = Start;
		ui.root.style.color = Color.rgb(0xFF0000);
		var n = new ImageNode();
		n.svg = icon;
		ui.root.append(n);
		ui.scale = 2;
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var drawn = [for (c in rec.calls) if (StringTools.startsWith(c, "image")) c];
		check("svg: an ImageNode its size, drawn at the window's pixels", n.width == 24 && n.height == 24 && drawn.length == 1 && StringTools.startsWith(drawn[0], "image 48x48 0 0 24 24")
			&& n.image.pixels.get(0) == 255 && n.image.pixels.get(2) == 0, drawn.join("|"));
		n.style.width = 40;
		ui.root.style.color = Color.rgb(0x0000FF);
		ui.update();
		rec = new Recording();
		ui.paint(rec);
		drawn = [for (c in rec.calls) if (StringTools.startsWith(c, "image")) c];
		check("svg: drawn again at a new size and colour", n.height == 40 && StringTools.startsWith(drawn[0], "image 80x80") && n.image.pixels.get(2) == 255, drawn.join("|"));
		// (a drawing shown by several nodes, or gone back to, rasterized once: a
		// ring whose drawing follows a value, as a game's health ring)
		var full = Svg.parse('<svg viewBox="0 0 8 8"><circle cx="4" cy="4" r="3" fill="currentColor"/></svg>');
		var a = new ImageNode(), b = new ImageNode();
		a.svg = full;
		b.svg = full;
		a.style.width = a.style.height = b.style.width = b.style.height = 16;
		ui.root.append(a);
		ui.root.append(b);
		ui.update();
		ui.paint(new Recording());
		var first = a.image;
		check("svg: one raster for the nodes showing a drawing at one size and colour", first != null && a.image == b.image);
		a.svg = icon;
		ui.update();
		ui.paint(new Recording());
		a.svg = full;
		ui.update();
		ui.paint(new Recording());
		check("svg: gone back to, the same raster", a.image == first);
		b.style.width = 20;
		ui.update();
		ui.paint(new Recording());
		check("svg: at another size, another", b.image != first && b.image.width == 40);
		// (bounded by bytes: a raster over RASTER_MAX not kept, many small ones
		// at most RASTER_BYTES; the cache's own count of its bytes)
		var big = ImageNode.raster(full, 1024, 1024, 0xFF000000);
		check("svg: a raster too large not kept", ImageNode.raster(full, 1024, 1024, 0xFF000000) != big);
		for (k in 0...400)
			ImageNode.raster(full, 64 + k, 64, 0xFF000000);
		check("svg: the kept rasters' bytes within the bound", ImageNode.rasterCacheBytes() <= ImageNode.RASTER_BYTES && ImageNode.rasterCacheBytes() > 0,
			"" + ImageNode.rasterCacheBytes());
	}

	// --- css ---

	// css/: colours against Chromium's computed ones (within 1 a channel),
	// gradients against its backgrounds (within 2 levels)
	static function css(here:String) {
		var dir = here + "/css";
		var colors:Array<{css:String, rgba:Array<Int>}> = haxe.Json.parse(sys.io.File.getContent(dir + "/colors.json"));
		var bad = [];
		for (c in colors) {
			var v = Color.tryParse(c.css);
			if (v == null || Math.abs(v.r - c.rgba[0]) > 1 || Math.abs(v.g - c.rgba[1]) > 1 || Math.abs(v.b - c.rgba[2]) > 1 || Math.abs(v.a - c.rgba[3]) > 1)
				bad.push(c.css + " " + (v == null ? "null" : v.toHex()) + " vs " + c.rgba.join(","));
		}
		check("css: colours as Chromium computes them (" + colors.length + ")", bad.length == 0, bad.join("; "));
		check("css: not a colour", Color.tryParse("bluish") == null && Color.tryParse("rgb(1, 2)") == null && Color.tryParse("#12345") == null);
		check("css: hex in either case, short and long", Color.tryParse("#AbCdEf") == Color.rgb(0xabcdef) && Color.tryParse("#F0a") == Color.rgb(0xff00aa)
			&& Color.tryParse("#0F08") == Color.rgba(0x00ff00, 0x88 / 255) && Color.tryParse(" #fff ") == Color.WHITE && Color.tryParse("#ggg") == null);
		check("css: toHex, and back", Color.rgba(0x3366ff, 0.5).toHex() == "#3366FF80" && Color.parse(Color.rgb(0xa1b2c3).toHex()) == Color.rgb(0xa1b2c3)
			&& Color.TRANSPARENT.toHex() == "#00000000", Color.rgba(0x3366ff, 0.5).toHex());
		var stats = Sys.getEnv("CSS_STATS") != null;
		var cases:Array<{name:String, css:String, width:Int, height:Int}> = haxe.Json.parse(sys.io.File.getContent(dir + "/gradients.json"));
		for (c in cases) {
			var img = Gradient.parse(c.css).render(c.width, c.height);
			var ref = PngDecoder.decode(sys.io.File.getBytes(dir + "/" + c.name + ".png"));
			var total = 0.0, worst = 0, a = img.pixels, b = ref.rgba;
			for (i in 0...c.width * c.height) {
				var o = i * 4, aa = a.get(o + 3), ba = b.get(o + 3), d = Std.int(Math.abs(aa - ba));
				for (k in 0...3) {
					var e = Std.int(Math.abs(a.get(o + k) * aa / 255 - b.get(o + k) * ba / 255));
					if (e > d) d = e;
				}
				total += d;
				if (d > worst) worst = d;
			}
			var mean = total / (c.width * c.height);
			if (stats) Sys.println('css ${c.name}: mean ${Math.round(mean * 100) / 100} worst $worst');
			check("css: " + c.name + " as Chromium draws it", mean < 1 && worst <= 2, 'mean $mean, worst $worst');
		}
		// a node's gradient: over its colour, under its border, at the window's pixels
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.alignItems = Start;
		var n = new Node("card");
		n.style.set({width: 40, height: 20, borderRadius: 4, background: Color.rgb(0xFFFFFF), borderWidth: 1, borderColor: Color.rgb(0x000000),
			backgroundImage: Gradient.parse("linear-gradient(to right, red, blue)")});
		ui.root.append(n);
		ui.scale = 2;
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (StringTools.startsWith(c, "rect") || StringTools.startsWith(c, "image")) c.split(" ").slice(0, 2).join(" ")];
		check("css: a node's gradient between its colour and its border", calls.join(",") == "rect 0,image 80x40,rect 0", calls.join(","));
		// each corner's radius and each side's border: drawn with them, the clip inside them
		var card = new Node("card2");
		card.style.set({width: 60, height: 40, corners: [12, 12, 0, 0], borders: [1, 2, 4, 2], borderColor: Color.rgb(0x000000), overflow: Hidden});
		ui.root.append(card);
		ui.scale = 1;
		ui.update();
		rec = new Recording();
		ui.paint(rec);
		var all = rec.calls.join("|");
		// (the clip: the padding box, each corner less the wider side meeting there)
		check("corners and sides: drawn with them, clipped inside them", all.indexOf("corners 12,12,0,0 sides 1,2,4,2") > 0
			&& all.indexOf("clip " + (card.absX + 2) + " " + (card.absY + 1) + " 56 35 0 corners 10,10,0,0") >= 0, all);
		ui.root.remove(card);
		ui.scale = 2;
		var img = n.backgroundImage(2);
		check("css: kept while the node's size stays", n.backgroundImage(2) == img && img.pixels.get(0) > 200 && img.pixels.get((79) * 4 + 2) > 200);
	}

	// CSS transforms: parsed and composed as CSS composes them, about the
	// origin; drawn by pushing the matrix around the subtree; hit and
	// pointed at through the inverse
	static function transforms() {
		function near(m:helder.canvas.Matrix, b:Array<Float>):Bool {
			var a = [m.a, m.b, m.c, m.d, m.e, m.f];
			for (i in 0...6)
				if (Math.abs(a[i] - b[i]) > 1e-9) return false;
			return true;
		}
		var m = Transform.parse("translate(10px, 50%) rotate(90deg) scale(2)").toMatrix(100, 40);
		check("transform: composed left to right", near(m, [0, 2, -2, 0, 10, 20]), "" + m);
		var t2 = Transform.parse("skewX(45deg) matrix(1, 0, 0, 1, 5, 6) rotate(0.25turn)").toMatrix(10, 10);
		check("transform: skew, matrix and turns", near(t2, [1, 1, -1, 0, 11, 6]), "" + t2);
		check("transform: none", Transform.parse("none").isIdentity());
		var bad = try {
			Transform.parse("spin(3deg)");
			false;
		} catch (e:Dynamic) true;
		check("transform: an unknown function is an error", bad);
		var built = new Transform(["translate", "rotate", "scale"], [[10, 50], [90], [2]], [[false, true], [false], [false]]).toMatrix(100, 40);
		var counted = try {
			new Transform(["translateX"], [[1, 2]]);
			false;
		} catch (e:Dynamic) true;
		check("transform: built without the text, as parse reads it; a wrong count an error", near(built, [m.a, m.b, m.c, m.d, m.e, m.f])
			&& new Transform(["translateX"], [[5]]).toMatrix(1, 1).e == 5 && counted, "" + built);
		var inv = new helder.canvas.Matrix();
		check("transform: inverted", m.invertInto(inv) && near(m.clone().multiply(inv), [1, 0, 0, 1, 0, 0]));
		var o = Transform.origin("left top");
		check("transform origin: keywords", o[0].resolve(80) == 0 && o[1].resolve(40) == 0);
		var o2 = Transform.origin("bottom");
		check("transform origin: one keyword, the other centred", o2[0].resolve(80) == 40 && o2[1].resolve(40) == 40);

		var ui = new Ui(new MonoText(), 300, 300);
		ui.root.style.alignItems = Start;
		var box = new Node("box");
		box.style.set({width: 100, height: 20, margin: 50, background: Color.rgb(0xFF0000)});
		var inner = new Node("inner");
		inner.style.set({width: 10, height: 10, background: Color.rgb(0x0000FF)});
		box.append(inner);
		ui.root.append(box);
		ui.update();
		// (rotated a quarter about its centre (100, 60): 100 wide becomes 100 high)
		box.style.transform = Transform.rotate(90);
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (!StringTools.startsWith(c, "text")) c];
		var first = calls.length > 0 ? calls[0].split(" ") : [];
		var drawn = first.length == 7 && first[0] == "transform" && Math.abs(Std.parseFloat(first[1])) < 1e-9 && Std.parseFloat(first[2]) == 1
			&& Std.parseFloat(first[3]) == -1 && Math.abs(Std.parseFloat(first[5]) - 160) < 1e-9 && Math.abs(Std.parseFloat(first[6]) - (-40)) < 1e-9;
		check("transform: pushed around the subtree", drawn && calls[calls.length - 1] == "popTransform", calls.join(" | "));
		var hitTop = ui.root.hitTest(100, 15), hitOld = ui.root.hitTest(140, 60);
		var wb = box.windowBounds();
		check("transform: its bounds where it is drawn", Math.abs(wb.x - 90) < 1e-9 && Math.abs(wb.y - 10) < 1e-9 && Math.abs(wb.width - 20) < 1e-9
			&& Math.abs(wb.height - 100) < 1e-9, wb.x + "," + wb.y + " " + wb.width + "x" + wb.height);
		inner.focusable = true;
		var at = ui.accessTree(), ids = [for (id in at.order) if (at.node(id) == inner) id], an = ids.length == 1 ? at.nodes.get(ids[0]) : null;
		check("transform: the accessibility tree's box through it", an != null && Math.abs(an.x - 100) < 1e-9 && Math.abs(an.y - 10) < 1e-9,
			an == null ? "none" : an.x + "," + an.y);
		inner.focusable = false;
		check("transform: hit through it", hitTop == box && hitOld == ui.root, hitTop + " " + hitOld);
		// (the inner box's top left (50, 50) turns to (110, 10): its 10x10 at x 100...110)
		var hitInner = ui.root.hitTest(105, 15);
		check("transform: children hit through their ancestor's", hitInner == inner, "" + hitInner);
		check("transform: local coordinates through it", Math.abs(box.localX(100, 15) - 5) < 1e-9 && Math.abs(box.localY(100, 15) - 10) < 1e-9,
			box.localX(100, 15) + "," + box.localY(100, 15));
		var at = [];
		box.onPointerDown = e -> at.push(e.localX + "," + e.localY);
		ui.pointerDown(102, 15, 1);
		ui.pointerUp(102, 15, 1);
		check("transform: events' local coordinates through it", at.length == 1 && at[0] == "5,8", at.join(" "));
		box.style.transformOrigin = Transform.origin("left top");
		box.style.transform = Transform.parse("scale(2)");
		ui.update();
		check("transform: about its origin", ui.root.hitTest(240, 85) == box && ui.root.hitTest(45, 55) == ui.root);
		box.style.transform = Transform.parse("scale(0)");
		ui.update();
		check("transform: flattened, it hits nothing", ui.root.hitTest(50, 50) == ui.root && box.hitTest(50, 50) == null);
		ui.root.remove(box);
	}

	// position: Sticky against Chromium's tops (a scroller 200x100, border 2,
	// padding 4: a header sticking 5 inside its content box within its
	// 120-high section; a footer sticking 3 above its bottom), at five scroll
	// positions
	// zIndex and order: painted and hit by them (zIndex, then positioned over
	// in-flow, then order); Tab still in the tree's order
	// vector paths (Canvas.path): filled, stroked, a gradient, even-odd, SVG's data
	static function paths() {
		inline function px(img:Image, x:Int, y:Int):Int
			return img.pixels.getInt32((y * img.width + x) * 4);
		var id = [1.0, 0, 0, 1, 0, 0];
		var sq = new Path().rect(2, 2, 6, 6).render(10, 10, id, Color.rgb(0xFF0000));
		check("paths: a filled rectangle", px(sq, 5, 5) == 0xFF0000FF && px(sq, 0, 0) == 0, StringTools.hex(px(sq, 5, 5)));
		var line = new Path().moveTo(0, 5).lineTo(10, 5).render(10, 10, id, null, {width: 2, paint: Color.BLACK});
		check("paths: a stroke, its width about the line", line.pixels.get((5 * 10 + 5) * 4 + 3) == 255 && line.pixels.get((1 * 10 + 5) * 4 + 3) == 0);
		var grad = new Path().rect(0, 0, 20, 4).render(20, 4, id, Gradient.parse("linear-gradient(to right, #ff0000, #0000ff)"));
		check("paths: a gradient over it", grad.pixels.get(4 * 1) > 200 && grad.pixels.get(4 * 18 + 2) > 200);
		var ring = new Path().rect(0, 0, 10, 10).rect(3, 3, 4, 4);
		ring.evenOdd = true;
		var hole = ring.render(10, 10, id, Color.BLACK);
		check("paths: even-odd leaves the inner one a hole", hole.pixels.get((5 * 10 + 5) * 4 + 3) == 0 && hole.pixels.get((1 * 10 + 1) * 4 + 3) == 255);
		var tri = new Path("M0 0 L10 0 L10 10 Z"), b = tri.bounds();
		var scaled = tri.render(20, 20, [2.0, 0, 0, 2, 0, 0], Color.BLACK);
		check("paths: SVG's data, its bounds, drawn at a scale", b.width == 10 && b.height == 10 && scaled.pixels.get((2 * 20 + 17) * 4 + 3) == 255
			&& scaled.pixels.get((17 * 20 + 2) * 4 + 3) == 0);
		var curve = new Path().moveTo(0, 0).quadTo(5, 10, 10, 0).arcTo(5, 5, 0, false, true, 0, 0).close();
		check("paths: curves made cubic", curve.commands.filter(c -> c == 2).length >= 2);
		var icon = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 4h16v16H4z" fill="currentColor"/></svg>');
		var drawn = icon.render(24, 24, Color.rgb(0x112233)), d:Drawing.ImageDrawing = drawn.drawing;
		check("paths: an svg's image keeps the drawing, for a writer's vectors", d != null && d.svg == icon && d.color == Color.rgb(0x112233));
	}

	// calc(): a percentage plus pixels, against the containing box as a percentage is
	static function calcs() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.alignItems = Start;
		var a = new Node(), b = new Node();
		a.style.width = "calc(100% - 20px)";
		a.style.height = "calc(50% + 2px)";
		b.style.width = 400;
		b.style.maxWidth = "calc(100% - 32px)";
		b.style.height = 10;
		ui.root.append(a);
		ui.root.append(b);
		ui.update();
		check("calc: a percentage minus or plus pixels; in a maximum", a.width == 180 && a.height == 52 && b.width == 168, a.width + " " + a.height + " " + b.width);
		check("calc: only pixels is pixels", Dim.parse("calc(10px + 4px)").equals(DimValue.Px(14)) && Dim.parse("calc(-50% - 1px)").equals(DimValue.Calc(-50, -1)));
		var bad = try {
			Dim.parse("calc(10em)");
			false;
		} catch (e:Dynamic) true;
		check("calc: another unit an error", bad);
	}

	static function stacking() {
		var ui = new Ui(new MonoText(), 200, 100);
		function box(tag:String, color:Int, x:Float):Node {
			var n = new Node(tag);
			n.style.set({width: 40, height: 40, background: Color.rgb(color), position: Absolute, left: x, top: 0});
			ui.root.append(n);
			return n;
		}
		var a = box("a", 0x110000, 10), b = box("b", 0x220000, 20), c = box("c", 0x330000, 30);
		ui.update();
		function painted():String {
			var rec = new Recording();
			ui.paint(rec);
			return [for (l in rec.calls) if (StringTools.startsWith(l, "rect")) l.split(" ")[6].substr(2, 2)].join(",");
		}
		check("stacking: the tree's order", painted() == "11,22,33" && ui.root.hitTest(35, 10) == c, painted());
		a.style.zIndex = 2;
		ui.update();
		check("stacking: a higher zIndex over the others, hit first", painted() == "22,33,11" && ui.root.hitTest(35, 10) == a, painted());
		c.style.zIndex = -1;
		ui.update();
		check("stacking: a negative one under", painted() == "33,22,11" && ui.root.hitTest(55, 10) == b, painted());
		// in the flow: order rearranges them; Tab follows the tree
		var ui2 = new Ui(new MonoText(), 200, 100);
		ui2.root.style.flexDirection = Row;
		var x = new Node("x"), y = new Node("y");
		for (n in [x, y]) {
			n.style.set({width: 40, height: 40});
			n.focusable = true;
			ui2.root.append(n);
		}
		y.style.order = -1;
		ui2.update();
		ui2.keyDown(Key.TAB, 0);
		check("stacking: order moves it, Tab keeps the tree's order", y.absX == 0 && x.absX == 40 && ui2.focus == x, '${y.absX} ${x.absX} ${ui2.focus}');
	}

	// visibility: hidden keeps the place, draws, hits, focuses and shows
	// nothing of the node, but a visible descendant still is
	static function visibility() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.flexDirection = Row;
		var a = new Node("a"), b = new Node("b"), inner = new Node("inner");
		for (n in [a, b]) {
			n.style.set({width: 60, height: 40, background: Color.rgb(n == a ? 0x110000 : 0x220000)});
			n.focusable = true;
			n.semantics = {role: Button, label: n.tag};
			ui.root.append(n);
		}
		inner.style.set({width: 20, height: 20, background: Color.rgb(0x330000)});
		inner.focusable = true;
		inner.semantics = {role: Button, label: "inner"};
		a.append(inner);
		a.style.visibility = Hidden;
		ui.update();
		function painted():String {
			var rec = new Recording();
			ui.paint(rec);
			return [for (l in rec.calls) if (StringTools.startsWith(l, "rect")) l.split(" ")[6].substr(2, 2)].join(",");
		}
		function labels():String {
			var at = ui.accessTree();
			return [for (id in at.order) if (at.nodes.get(id).name != null && at.nodes.get(id).name != "") at.nodes.get(id).name].join(",");
		}
		check("visibility: hidden keeps its place, not drawn", b.absX == 60 && painted() == "22", painted());
		check("visibility: hidden not hit, nor focused, nor seen", ui.root.hitTest(30, 30) == ui.root && labels() == "b" && {
			ui.keyDown(Key.TAB, 0);
			ui.focus == b;
		}, labels());
		// (its ring not drawn)
		ui.setFocus(null);
		inner.style.visibility = Visible;
		ui.update();
		check("visibility: a visible descendant drawn, hit, seen", painted() == "33,22" && ui.root.hitTest(10, 10) == inner && labels() == "inner,b",
			painted() + " " + labels());
		a.style.visibility = null;
		ui.update();
		check("visibility: shown again", painted() == "11,33,22" && ui.root.hitTest(30, 30) == a, painted());
	}

	// right to left, a row overflowing a scroller overflows on the left:
	// scrolled there by negative offsets (Chromium's scrollLeft), from 0 at
	// its right end; the vertical bar on the left
	// pointerEvents None: the pointer through to what is under it; an Auto descendant still found
	static function pointerEvents() {
		var ui = new Ui(new MonoText(), 200, 100);
		var under = new Node("under"), cover = new Node("cover"), knob = new Node("knob");
		under.style.set({width: 100, height: 50});
		cover.style.set({position: Absolute, left: 0, top: 0, width: 100, height: 50, pointerEvents: None});
		knob.style.set({width: 20, height: 20, pointerEvents: Auto});
		cover.append(knob);
		ui.root.append(under);
		ui.root.append(cover);
		ui.update();
		var clicked = 0;
		under.onClick = _ -> clicked++;
		ui.pointerDown(50, 30, 1);
		ui.pointerUp(50, 30, 1);
		check("pointer events: through a None node to the one under it", ui.root.hitTest(50, 30) == under && clicked == 1, "" + ui.root.hitTest(50, 30));
		check("pointer events: its Auto child still found", ui.root.hitTest(10, 10) == knob);
	}

	// the platform's scroll views (Ui.nativeScroll): the scrollers listed
	// where they show, a drag given to the one that can move that way, their
	// offsets taken (past the ends while bouncing), helder's drag off
	static function nativeScrolls() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.nativeScroll = true;
		var outer = new Node("outer"), row = new Node("row"), tall = new Node("tall");
		outer.style.set({width: 200, height: 100, overflow: Scroll});
		row.style.set({height: 40, flexShrink: 0, overflow: Scroll, flexDirection: Row});
		for (i in 0...3) {
			var c = new Node("c" + i);
			c.style.set({width: 100, height: 40, flexShrink: 0});
			row.append(c);
		}
		tall.style.set({height: 300, flexShrink: 0});
		outer.append(row);
		outer.append(tall);
		ui.root.append(outer);
		ui.update();
		var vs = ui.scrollViews();
		check("native scroll: both scrollers, outer first", vs.length == 2 && vs[0].node == outer && vs[1].node == row, "" + vs.length);
		check("native scroll: extents", vs[0].contentHeight == 340 && !vs[0].scrollsX && vs[0].scrollsY && vs[1].contentWidth == 300 && vs[1].scrollsX,
			vs[0].contentHeight + " " + vs[1].contentWidth);
		check("native scroll: a vertical drag on the row the outer's", ui.nativeBegins(outer, 50, 20, 0, 10) && !ui.nativeBegins(row, 50, 20, 0, 10));
		check("native scroll: a sideways one the row's", ui.nativeBegins(row, 50, 20, 10, 0) && !ui.nativeBegins(outer, 50, 20, 10, 0));
		check("native scroll: at the top, pulled down, the outer's (bouncing)", ui.nativeBegins(outer, 50, 20, 0, -10));
		ui.nativeScrolled(outer, 0, 30);
		ui.update();
		vs = ui.scrollViews();
		check("native scroll: its offset taken, the row moved up", outer.scrollY == 30 && vs.length == 2 && vs[1].y == -30, outer.scrollY + " " + vs[1].y);
		ui.nativeScrolled(outer, 0, -12);
		check("native scroll: past the start while bouncing", outer.scrollY == -12);
		ui.nativeScrolled(outer, 0, 0);
		ui.update();
		var moved = false;
		tall.onPointerMove = _ -> moved = true;
		check("native scroll: none over a node following the pointer", !ui.nativeBegins(outer, 50, 80, 0, 10));
		tall.onPointerMove = null;
		ui.pointerDown(50, 80, 1, 1, Touch);
		ui.pointerMove(50, 40, 1);
		ui.pointerUp(50, 40, 1, 1);
		ui.update();
		check("native scroll: a finger's drag left to the platform", outer.scrollY == 0, "" + outer.scrollY);
		var clicks = 0;
		tall.onClick = _ -> clicks++;
		ui.nativeHalt = () -> true;
		ui.pointerDown(50, 80, 1, 1, Touch);
		ui.pointerUp(50, 80, 1, 1);
		check("native scroll: a touch stopping a glide clicks nothing", clicks == 0, "" + clicks);
		ui.nativeHalt = null;
		ui.nativeScroll = false;
		ui.pointerDown(50, 80, 1, 1, Touch);
		ui.pointerMove(50, 40, 1);
		ui.pointerUp(50, 40, 1, 1);
		check("native scroll: off, helder's own drag scrolls", outer.scrollY > 0, "" + outer.scrollY);
	}

	// overlay scrollbars (Ui.overlayBars, helder's plain ones): none at rest,
	// shown as the pointer comes to the edge (a frame asked for), taken by a
	// press there and dragged, faded once left alone
	static function overlayBars() {
		var time = 100.0;
		Ui.now = () -> time;
		var ui = new Ui(new MonoText(), 200, 100);
		ui.overlayBars = true;
		var page = new Node("page"), tall = new Node("tall");
		page.style.set({width: 200, height: 100, overflow: Scroll});
		tall.style.set({height: 400, flexShrink: 0});
		page.append(tall);
		ui.root.append(page);
		ui.update();
		ui.paint(new Recording());
		check("overlay bars: none at rest", @:privateAccess ui.barShown(page) == 0);
		ui.pointerMove(100, 50);
		ui.update();
		ui.paint(new Recording());
		@:privateAccess ui.needsFrame = false;
		ui.pointerMove(197, 10);
		check("overlay bars: the pointer at the edge asks for a frame", @:privateAccess ui.needsFrame);
		ui.update();
		ui.paint(new Recording());
		check("overlay bars: shown near the edge", @:privateAccess ui.barShown(page) == 1);
		ui.pointerDown(197, 10, 1);
		ui.pointerMove(197, 60);
		ui.pointerUp(197, 60, 1);
		check("overlay bars: its thumb dragged", page.scrollY > 100, "" + page.scrollY);
		ui.pointerMove(100, 50);
		ui.update();
		ui.paint(new Recording());
		time += 1;
		ui.update();
		ui.paint(new Recording());
		check("overlay bars: faded once left alone", @:privateAccess ui.barShown(page) == 0);
	}

	// a trackpad's gestures as macOS's views take them (Ui.elastic): latched
	// to one scroller, stretching past an end and springing back, the
	// momentum replayed at the frames' times and bouncing at an end; overlay
	// scrollbars fading after the scroll
	static function trackpad() {
		var time = 100.0;
		Ui.now = () -> time;
		var ui = new Ui(new MonoText(), 200, 100);
		ui.elastic = true;
		ui.overlayBars = true;
		var page = new Node("page"), row = new Node("row"), tall = new Node("tall");
		page.style.set({width: 200, height: 100, overflow: Scroll});
		row.style.set({height: 40, flexShrink: 0, overflow: Scroll, flexDirection: Row});
		for (i in 0...3) {
			var c = new Node("c" + i);
			c.style.set({width: 100, height: 40, flexShrink: 0});
			row.append(c);
		}
		tall.style.set({height: 300, flexShrink: 0});
		page.append(row);
		page.append(tall);
		ui.root.append(page);
		ui.update();
		ui.paint(new Recording());
		check("trackpad: no overlay bar before a scroll", @:privateAccess ui.barShown(page) == 0);
		inline function wheel(dy:Float, phase:Int, momentum = 0, dx = 0.0, y = 20.0)
			ui.wheel(50, y, dx, dy, false, 0, phase, momentum, time);
		function frames(seconds:Float) {
			var end = time + seconds;
			while (time < end) {
				time += 1 / 120;
				Clock.tick(time);
			}
		}
		// (a vertical gesture over the row: the page's, the row cannot move that way)
		wheel(0, 1);
		wheel(30, 2);
		check("trackpad: latched to the page over the row", page.scrollY == 30 && row.scrollX == 0, page.scrollY + " " + row.scrollX);
		// (sideways in the same gesture: still the page's, which cannot: nothing)
		wheel(0, 2, 0, 50);
		check("trackpad: no handoff mid-gesture", row.scrollX == 0, "" + row.scrollX);
		wheel(0, 3);
		// (past the start: a stretch, less than the push, springing back once let go)
		time += 1;
		wheel(0, 1);
		wheel(-100, 2);
		var s = page.scrollY;
		// (from 30, 100 up: 70 past the start of a 100-point view, AppKit's curve and trackpad coefficient: 4.99)
		check("trackpad: past the start, stretched as AppKit's", Math.abs(s + 4.988) < 0.01, "" + s);
		time += 0.2;
		wheel(0, 3);
		frames(0.1);
		check("trackpad: springing back", page.scrollY > s && page.scrollY < 0, "" + page.scrollY);
		frames(1);
		check("trackpad: back at the start", page.scrollY == 0, "" + page.scrollY);
		// (a vertical swipe drifting sideways: no sideways stretch where nothing scrolls that way; a small push past the
		// end none either)
		time += 1;
		wheel(0, 1);
		wheel(-6, 2, 0, -3);
		check("trackpad: no stretch sideways, none under 10 points", page.scrollX == 0 && page.scrollY == 0, page.scrollX + " " + page.scrollY);
		wheel(0, 3);
		frames(1);
		// (a fling: the momentum's deltas replayed between the frames, all of them in the end)
		time += 1;
		wheel(0, 1);
		wheel(10, 2, 0, 0, 80);
		time += 0.01;
		wheel(10, 2, 0, 0, 80);
		wheel(0, 3);
		for (i in 0...6) {
			wheel(8, 0, i == 0 ? 1 : 2, 0, 80);
			frames(1 / 60);
		}
		wheel(0, 0, 3);
		frames(0.2);
		check("trackpad: the momentum replayed, all of it", Math.abs(page.scrollY - 68) < 0.01, "" + page.scrollY);
		// (a fling into the end: a bounce past it, back at the end after)
		time += 1;
		wheel(0, 1);
		wheel(60, 2, 0, 0, 80);
		time += 0.01;
		wheel(60, 2, 0, 0, 80);
		wheel(0, 3);
		var past = 0.0;
		for (i in 0...10) {
			wheel(40, 0, i == 0 ? 1 : 2, 0, 80);
			frames(1 / 60);
			past = Math.max(past, page.scrollY - 240);
		}
		wheel(0, 0, 3);
		frames(1.5);
		check("trackpad: a fling into the end bounces past it and back", past > 0 && page.scrollY == 240, past + " " + page.scrollY);
		// (a mouse wheel turned on, a notch every frame: the glide moving on (no notch restarting it from rest), faster as notches come,
		// as Chromium's; all of it in the end)
		ui.elastic = false;
		page.scrollY = 0;
		time += 1;
		Clock.tick(time);
		var at = [];
		for (i in 0...6) {
			ui.wheel(50, 80, 0, 20, true);
			time += 1 / 60;
			Clock.tick(time);
			at.push(page.scrollY);
		}
		var flows = true;
		for (i in 1...at.length)
			if (at[i] <= at[i - 1]) flows = false;
		check("trackpad: a wheel turned on glides, faster as notches come (eased in from rest, as Chromium)", at[1] > 0 && flows && at[5] > 15 && at[5] - at[4] > at[2] - at[1], "" + at);
		frames(0.5);
		check("trackpad: the wheel's notches all scrolled in the end", page.scrollY == 120, "" + page.scrollY);
		ui.elastic = true;
		// (Linux's touchpads, GTK's kinetic glide: no Began, Changed moves, Ended at the fingers' lift; the glide v / 4 on,
		// a glide into an end bouncing past it and back)
		ui.elastic = false;
		ui.kinetic = true;
		page.scrollY = 0;
		time += 1;
		for (i in 0...5) {
			wheel(10, 2);
			time += 0.02;
		}
		wheel(0, 3);
		var lifted = page.scrollY;
		frames(3);
		// (50 over the last 100 ms: 500 a second, 125 more)
		check("trackpad: Linux's glide after the lift, GTK's", lifted == 50 && Math.abs(page.scrollY - 175) < 1.5, lifted + " " + page.scrollY);
		time += 1;
		for (i in 0...5) {
			wheel(15, 2);
			time += 0.01;
		}
		wheel(0, 3);
		var top = 0.0;
		for (i in 0...120) {
			time += 1 / 120;
			Clock.tick(time);
			top = Math.max(top, page.scrollY);
		}
		check("trackpad: a glide into the end bounces past it, back at the end", top > 240 && page.scrollY == 240, top + " " + page.scrollY);
		ui.kinetic = false;
		ui.elastic = true;
		// (overlay scrollbars: shown as it moves, gone a while after)
		ui.update();
		ui.paint(new Recording());
		check("trackpad: the overlay bar shown after a scroll", @:privateAccess ui.barShown(page) > 0);
		time += 1;
		check("trackpad: the overlay bar faded a second later", @:privateAccess ui.barShown(page) == 0);
		Ui.now = haxe.Timer.stamp;
	}

	// Android's fling (helder.os.android.Fling: a least-squares speed, OverScroller's
	// spline) and its stretch past an end (Ui.stretch: Flutter's port of
	// Android 12's)
	static function androidScroll() {
		var f = new helder.os.android.Fling();
		f.start(0);
		for (i in 1...6)
			f.move(0, 10, i * 10.0);
		var v = f.velocity(50);
		check("android: a drag's speed fitted (1000 a second)", Math.abs(v.y - 1000) < 1 && v.x == 0, v.y + "");
		check("android: none once it stood still 40 ms", f.velocity(100).y == 0);
		var slow = new helder.os.android.Fling();
		slow.start(0);
		for (i in 1...4)
			slow.move(0, 120, i * 120.0);
		check("android: moves further apart than the horizon still a speed (the last two)", Math.abs(slow.velocity(360).y - 1000) < 1, "" + slow.velocity(360).y);
		check("android: a fling past 50 a second", f.release(50));
		var sum = 0.0, steps = 0, last = 1e9, slowing = true;
		var t = 50.0;
		while (f.step(t += 1000 / 60) || f.gliding) {
			sum += f.dy;
			if (f.dy > last + 1e-9) slowing = false;
			last = f.dy;
			if (++steps > 600) break;
		}
		// (OverScroller's distance for 1000 points a second: 0.015 * 0.84 * g * 39.37 * 160 * e^(2.358 / 1.358 * ln(0.35 * 1000 / (0.015 * that))))
		var coeff = 0.015 * 9.80665 * 39.37 * 160 * 0.84, l = Math.log(0.35 * 1000 / coeff), d = coeff * Math.exp(2.3582018 / 1.3582018 * l);
		check("android: the fling goes OverScroller's distance, slowing", Math.abs(sum - d) < 0.5 && slowing, sum + " " + d);
		f.start(0);
		f.move(0, 1, 100);
		check("android: no fling under 50 a second", !f.release(100));

		var time = 100.0;
		Ui.now = () -> time;
		var ui = new Ui(new MonoText(), 200, 100);
		ui.stretch = true;
		var page = new Node("page"), tall = new Node("tall");
		page.style.set({width: 200, height: 100, overflow: Scroll});
		tall.style.set({height: 300, flexShrink: 0});
		page.append(tall);
		ui.root.append(page);
		ui.update();
		var st = @:privateAccess ui.stretcher;
		@:privateAccess st.drag(50, 50, 0, -50);
		// (50 past the start of a 100-point view: 0.016 (0.5 + 1 - e^(-0.5 e / 0.33)))
		var want = -0.016 * (0.5 + 1 - Math.exp(-0.5 * Math.exp(1) / 0.33));
		check("android: a drag past the start stretches, Flutter's curve", page.scrollY == 0 && Math.abs(@:privateAccess st.amount - want) < 1e-9, @:privateAccess st.amount + " " + want);
		@:privateAccess st.drag(50, 50, 0, 70);
		check("android: pulled back, the stretch gives first, then it scrolls", @:privateAccess st.amount == 0 && page.scrollY == 20, @:privateAccess st.amount + " " + page.scrollY);
		@:privateAccess st.drag(50, 50, 0, 200);
		check("android: past the end, stretched the other way", page.scrollY == 200 && @:privateAccess st.amount > 0);
		var before = @:privateAccess st.amount;
		@:privateAccess st.drag(50, 50, 0, 30);
		check("android: pushed on at the end (the drag latched to it), stretched further", @:privateAccess st.amount > before, before + " " + @:privateAccess st.amount);
		@:privateAccess st.release(0);
		for (i in 0...120) {
			time += 1 / 60;
			Clock.tick(time);
		}
		check("android: let go, it springs back", @:privateAccess st.amount == 0 && @:privateAccess st.node == null, "" + @:privateAccess st.amount);
		// (a finger's fling with the stretch on: it glides on, nothing left over mid-way taken for an end)
		@:privateAccess ui.touchScroll.g = new helder.os.android.Fling();
		page.scrollY = 0;
		tall.style.height = 5000;
		page.style.height = 100;
		ui.update();
		var t0 = time;
		ui.pointerDown(100, 90, 1, 1, Touch, 1, t0);
		for (i in 1...11)
			ui.pointerMove(100, 90 - 8 * i, 1, 1, t0 + i * 0.008);
		ui.pointerUp(100, 10, 1, 1, t0 + 0.081);
		var dragged = page.scrollY;
		for (i in 0...60) {
			time += 1 / 60;
			ui.update();
			Clock.tick(time);
		}
		check("android: a fling glides on past the drag (OverScroller's 194 for 1000 a second)", Math.abs(page.scrollY - dragged - 194) < 2, dragged + " " + page.scrollY);
		Ui.now = haxe.Timer.stamp;
	}

	// (an offset the program sets once its bars faded: a frame asked for)
	static function scrollSet() {
		var ui = new Ui(new MonoText(), 200, 100), list = new Node(), tall = new Node();
		list.style.set({width: 200, height: 100, overflow: Scroll});
		tall.style.set({height: 2000, flexShrink: 0});
		list.append(tall);
		ui.root.append(list);
		var t = 1.0;
		Ui.now = () -> t;
		for (_ in 0...3) {
			ui.update();
			ui.paint(new Recording());
		}
		list.scrollY = 600;
		ui.update();
		ui.paint(new Recording());
		t += 10;
		ui.update();
		ui.paint(new Recording());
		var rest = ui.needsFrame;
		list.scrollY = 300;
		check("a scroll offset set at rest asks for a frame", !rest && ui.needsFrame, '$rest ${ui.needsFrame}');
		Ui.now = haxe.Timer.stamp;
	}

	static function rtlScroll() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.scrollDuration = 0;
		var s = new Node("s");
		s.style.set({width: 100, height: 50, overflow: Scroll, flexDirection: Row, direction: Rtl});
		for (i in 0...3) {
			var c = new Node("c" + i);
			c.style.set({width: 60, height: 20, flexShrink: 0});
			s.append(c);
		}
		ui.root.append(s);
		ui.update();
		var c2 = s.children[2];
		check("rtl scroll: the content to the left counted", s.contentWidth == 180 && s.scrollX == 0 && c2.absX == -80, s.contentWidth + " " + c2.absX);
		ui.scrollBy(s, -1000, 0);
		ui.update();
		check("rtl scroll: scrolled left to its end", s.scrollX == -80 && ui.root.hitTest(5, 10) == c2, s.scrollX + " " + ui.root.hitTest(5, 10));
		ui.scrollBy(s, 1000, 0);
		check("rtl scroll: back to 0 at most", s.scrollX == 0, "" + s.scrollX);
		// (a column taller than it: its bar on the left)
		var t = new Node("t");
		t.style.set({width: 100, height: 50, overflow: Scroll, direction: Rtl});
		var tall = new Node("tall");
		tall.style.set({height: 200, flexShrink: 0});
		t.append(tall);
		ui.root.append(t);
		ui.update();
		var bar:Array<Float> = @:privateAccess Scrolling.thumb(t, false);
		check("rtl scroll: the vertical bar on the left", bar != null && bar[0] == t.absX + Ui.SCROLLBAR_INSET, "" + bar);
		// (scrollbar-width: thin, two thirds as thick; none, no bar to draw or grab, still scrolled by the wheel; colours inherited)
		t.style.scrollbarWidth = Thin;
		var thin:Array<Float> = @:privateAccess Scrolling.thumb(t, false);
		t.style.scrollbarWidth = None;
		var none:Array<Float> = @:privateAccess Scrolling.thumb(t, false);
		ui.wheel(t.absX + 50, t.absY + 20, 0, 30);
		ui.update();
		ui.root.style.scrollbarColor = Color.rgb(0xFF0000);
		check("scrollbars: thin, none (the wheel still scrolls), the colour inherited", thin != null && thin[2] == 4 && none == null && t.scrollY == 30
			&& @:privateAccess Scrolling.inheritedBar(t, false) == Color.rgb(0xFF0000) && @:privateAccess Scrolling.inheritedBar(t, true) == null, thin + " " + t.scrollY);
	}

	// textWrap NoWrap (inherited): a line kept whole past its box, its
	// min-content as wide; Wrap again inside
	static function noWrap() {
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.alignItems = Start;
		var box = new Node("box"), t = new TextNode("one two three");
		box.style.set({width: 40, textWrap: NoWrap});
		box.append(t);
		ui.root.append(box);
		ui.update();
		var p = t.laidOut(), whole = p.width;
		check("no wrap: one line, past its box", p.lineCount == 1 && t.width == 40 && whole > 40, p.lineCount + " " + whole);
		box.style.width = DimValue.Auto;
		var row = new Node("row");
		row.style.set({width: 10, flexDirection: Row});
		ui.root.append(row);
		var u = new TextNode("alpha beta");
		row.append(u);
		row.style.textWrap = NoWrap;
		ui.update();
		check("no wrap: the min-content width the whole line", u.width == u.laidOut().width && u.laidOut().lineCount == 1, "" + u.width);
		t.style.textWrap = Wrap;
		box.style.width = 40;
		ui.update();
		check("no wrap: Wrap again inside", t.laidOut().lineCount > 1, "" + t.laidOut().lineCount);
		// text-overflow: ellipsis: the line cut within its box, its intrinsic width the whole text's
		t.style.textWrap = NoWrap;
		t.style.textOverflow = Ellipsis;
		ui.update();
		var m:MonoText.MonoParagraph = cast t.laidOut();
		check("text overflow: one line cut to its box with an ellipsis", m.lineCount == 1 && m.ellipsis && m.width <= 40 && t.minContentWidth(ui.text) > 40,
			m.lineCount + " " + m.width);
		box.style.width = 400;
		ui.update();
		check("text overflow: none where it fits", !(cast t.laidOut() : MonoText.MonoParagraph).ellipsis);
	}

	// textTransform (inherited): the letters shown, the indices kept; a span its own
	static function textTransform() {
		var ui = new Ui(new MonoText(), 300, 200);
		var box = new Node("box"), t = new TextNode("hello big world");
		box.append(t);
		ui.root.append(box);
		box.style.textTransform = Uppercase;
		ui.update();
		check("text transform: inherited, upper case", t.allText() == "HELLO BIG WORLD" && t.text == "hello big world", t.allText());
		t.style.textTransform = Capitalize;
		ui.update();
		check("text transform: each word's first letter", t.allText() == "Hello Big World", t.allText());
		var rich = new TextNode(""), a = new TextNode("one "), b = new TextNode("two");
		rich.append(a);
		rich.append(b);
		b.style.textTransform = Lowercase;
		box.append(rich);
		ui.update();
		check("text transform: a span its own", rich.allText() == "ONE two", rich.allText());
	}

	static function sticky() {
		var ui = new Ui(new MonoText(), 300, 300);
		ui.root.style.alignItems = Start;
		var s = new Node("s");
		s.style.set({width: 200, height: 100, overflow: Scroll, borderWidth: 2, padding: 4});
		function block(h:Float):Node {
			var n = new Node();
			n.style.set({height: h, flexShrink: 0});
			return n;
		}
		var sec = block(120);
		sec.style.padding = 6;
		var h = block(20);
		h.style.set({position: Sticky, top: 5});
		sec.append(h);
		sec.append(block(20));
		var f = block(10);
		f.style.set({position: Sticky, bottom: 3});
		for (c in [block(30), sec, block(200), f, block(100)])
			s.append(c);
		ui.root.append(s);
		ui.update();
		var got = [], want = "0:42,81 50:11,81 100:11,81 140:-10,81 372:-242,-16";
		for (st in [0.0, 50, 100, 140, 400]) {
			ui.scrollTo(s, 0, st);
			got.push(s.scrollY + ":" + h.windowBounds().y + "," + f.windowBounds().y);
		}
		check("sticky: where Chromium sticks it as it scrolls", got.join(" ") == want, got.join(" "));
		ui.scrollTo(s, 0, 100);
		check("sticky: hit where it sticks", ui.root.hitTest(50, 15) == h, "" + ui.root.hitTest(50, 15));
		// (over what scrolls under it: drawn after its siblings)
		sec.children[1].style.background = Color.rgb(0x00FF00);
		h.style.background = Color.rgb(0xFF0000);
		// (h is first in the section, its sibling after it)
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var order = [for (c in rec.calls) if (c.indexOf("ff00ff00") > 0) "green" else if (c.indexOf("ffff0000") > 0) "red"].filter(x -> x != null);
		check("sticky: drawn over its siblings", order.join(",") == "green,red", order.join(","));
		// (an absolute box first, an in-flow one under it after: drawn and hit over it)
		var ui2 = new Ui(new MonoText(), 100, 100);
		var abs = new Node("abs");
		abs.style.set({position: Absolute, left: 0, top: 0, width: 50, height: 50, background: Color.rgb(0xFF0000)});
		var flow = new Node("flow");
		flow.style.set({height: 50, background: Color.rgb(0x00FF00)});
		ui2.root.append(abs);
		ui2.root.append(flow);
		ui2.update();
		var rec2 = new Recording();
		ui2.paint(rec2);
		var order2 = [for (c in rec2.calls) if (c.indexOf("ff00ff00") > 0) "green" else if (c.indexOf("ffff0000") > 0) "red"].filter(x -> x != null);
		check("absolute: drawn and hit over its in-flow siblings", order2.join(",") == "green,red" && ui2.root.hitTest(10, 10) == abs, order2.join(","));
	}

	// what a frame leaves out: rows out of a scroller's view not drawn (those
	// in it all drawn), a clean tree not laid out again, the accessibility
	// tree kept until something it reads changes
	static function culling() {
		var ui = new Ui(new MonoText(), 200, 200);
		var list = new Node("list");
		list.style.set({height: 100, overflow: Scroll});
		for (i in 0...100) {
			var row = new Node("row" + i);
			row.style.set({height: 20, flexShrink: 0, background: Color.rgb(0x010000 * (i + 1))});
			row.focusable = true;
			list.append(row);
		}
		ui.root.append(list);
		ui.update();
		ui.scrollTo(list, 0, 500);
		var rec = new Recording();
		ui.paint(rec);
		var rows = [for (c in rec.calls) if (StringTools.startsWith(c, "rect")) c];
		var visible = [for (i in 25...30) "ff" + StringTools.hex(i + 1, 2).toLowerCase() + "0000"];
		check("culling: the rows in view drawn, not the others", rows.length >= 5 && rows.length <= 14 && visible.filter(v -> rows.join("|").indexOf(v) < 0).length == 0,
			rows.length + " " + rows.join("|"));
		check("culling: hit in the scrolled view", ui.root.hitTest(10, 30) == list.children[26], "" + ui.root.hitTest(10, 30));
		var a = ui.accessTree(), b = ui.accessTree();
		list.children[3].semantics = {label: "third"};
		var c = ui.accessTree();
		ui.scrollTo(list, 0, 520);
		var d = ui.accessTree();
		check("culling: the accessibility tree kept, built again after a change", a == b && c != b && d != c);
		var laid = @:privateAccess Layout.run(ui.root, 200, 200, ui.text);
		list.children[2].style.height = 30;
		var again = @:privateAccess Layout.run(ui.root, 200, 200, ui.text);
		check("culling: a clean tree not laid out, a changed one laid out", !laid && again && list.children[3].y == 70, list.children[3].y + "");
	}

	// a tree painted through its display list (Ui.paint: recorded, then
	// replayed) gives its canvas the calls painting it directly does, with
	// the same objects: random trees changed at random over frames
	static function replayed() {
		var seed = 7, bad = 0, frames = 0, first = "";
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var words = ["a", "bb", "ccc dd", "eeee f gg", "hhhhhhh"], img = new Image(8, 6), line = new Path().moveTo(0, 0).lineTo(20, 10);
		var nodes:Array<Node> = [];
		function restyle(n:Node) {
			var s = n.style;
			switch rnd(16) {
				case 0: s.width = [30, 60, 120][rnd(3)];
				case 1: s.height = [20, 50, 300][rnd(3)];
				case 2: s.background = Color.rgba(rnd(255), [0, 0.5, 1][rnd(3)]);
				case 3:
					s.borderWidth = rnd(3);
					s.borderColor = Color.rgba(0x204060, [0.5, 1][rnd(2)]);
				case 4: s.borders = [rnd(3), 0, rnd(4), 1];
				case 5: s.borderRadius = rnd(3) * 4;
				case 6: s.corners = CornersValue.parse(["4px 0 8px 2px", "10px"][rnd(2)]);
				case 7: s.borderStyle = [BorderStyle.Solid, BorderStyle.Dashed, BorderStyle.Dotted][rnd(3)];
				case 8: s.opacity = [1, 0.5, 0][rnd(3)];
				case 9: s.boxShadow = rnd(3) == 0 ? null : Shadow.parse(["0 4px 12px rgba(0,0,0,0.5)", "inset 2px 2px 4px #00000080", "0 0 0 2px #ff0000"][rnd(3)]);
				case 10: s.transform = rnd(2) == 0 ? null : Transform.parse(["translate(30px, 10px)", "scale(1.5)", "rotate(10deg)"][rnd(3)]);
				case 11: s.overflow = [Overflow.Visible, Overflow.Hidden, Overflow.Scroll][rnd(3)];
				case 12: s.textShadow = rnd(2) == 0 ? null : Shadow.parse("1px 1px 2px #000000");
				case 13: s.visibility = [null, Visibility.Hidden, Visibility.Visible][rnd(3)];
				case 14: s.flexDirection = [Direction.Row, Direction.Column][rnd(2)];
				case _: s.padding = rnd(3) * 3;
			}
		}
		function make(depth:Int):Node {
			var n = switch rnd(depth == 3 ? 3 : 6) {
				case 0: new TextNode(words[rnd(words.length)]);
				case 1: new ImageNode(img);
				case 2: new Stroked(line);
				case _: new Node();
			}
			n.style.background = Color.rgb(0x101010 * (1 + nodes.length % 15));
			nodes.push(n);
			if (!n.hasContent())
				for (i in 0...rnd(4))
					n.append(make(depth + 1));
			for (i in 0...rnd(4))
				restyle(n);
			return n;
		}
		for (tree in 0...30) {
			var ui = new Ui(new MonoText(), 240, 200);
			nodes.resize(0);
			ui.root.append(make(0));
			for (frame in 0...12) {
				for (i in 0...rnd(4)) {
					var n = nodes[rnd(nodes.length)];
					if (n.ui == null) continue;
					switch rnd(5) {
						case 0 if (Std.isOfType(n, TextNode)): (cast n : TextNode).text = words[rnd(words.length)];
						case 1 if (!n.hasContent()): n.append(make(2));
						case 2 if (n.parent != null && n.parent != ui.root): n.parent.remove(n);
						case 3 if (n.style.overflow == Scroll): ui.scrollTo(n, 0, rnd(40));
						case _: restyle(n);
					}
				}
				ui.update();
				// (one paint, straight into a log and into a list replayed into another: the same
				// objects; then Ui.paint's, through its own list, against a direct one's values)
				var direct = new Calls(), replayed = new Calls(), list = new helder.ui.draw.DisplayList();
				ui.direct = true;
				ui.paint(new Tee(direct, list));
				list.replay(replayed);
				var want = new Recording(), got = new Recording();
				ui.paint(want);
				ui.direct = false;
				ui.paint(got);
				frames++;
				if (!direct.same(replayed) || want.calls.join("|") != got.calls.join("|")) {
					bad++;
					if (first == "") first = 'tree $tree frame $frame: ${direct.log.length} against ${replayed.log.length}';
				}
			}
		}
		check("paint: replayed from the display list, as painted directly", bad == 0 && frames == 360, '$bad of $frames frames differ, first $first');
	}

	// layered painting (Ui.paint: each layer's list kept while nothing it
	// paints changes, walked onto the canvas) gives a canvas the calls a
	// direct paint gives it: two copies of random trees (scrollers and their
	// sticky rows, nodes whose transform and opacity move every frame,
	// motion's entering and leaving rows), changed at random over frames, one
	// painted directly, the other through its layers
	static function layered() {
		var bad = 0, frames = 0, first = "", records = 0, copies = 0;
		var words = ["a", "bb", "ccc dd", "eeee f gg"], img = new Image(8, 6), line = new Path().moveTo(0, 0).lineTo(20, 10);
		inline function next(seed:Int):Int
			return (seed * 1103515245 + 12345) & 0x7fffffff;
		function restyle(n:Node, r:Int->Int) {
			var s = n.style;
			switch r(15) {
				case 13: s.display = r(4) == 0 ? Display.None : Display.Flex;
				case 0: s.width = [30, 60, 120][r(3)];
				case 1: s.height = [20, 50, 300][r(3)];
				case 2: s.background = Color.rgba(r(255), [0, 0.5, 1][r(3)]);
				case 3:
					s.borderWidth = r(3);
					s.borderColor = Color.rgba(0x204060, [0.5, 1][r(2)]);
				case 4: s.borderRadius = r(3) * 4;
				case 5: s.opacity = [1, 0.5, 0][r(3)];
				case 6: s.boxShadow = r(3) == 0 ? null : Shadow.parse(["0 4px 12px rgba(0,0,0,0.5)", "inset 2px 2px 4px #00000080"][r(2)]);
				case 7: s.transform = r(2) == 0 ? null : Transform.parse(["translate(30px, 10px)", "scale(1.5)", "rotate(10deg)"][r(3)]);
				case 8: s.overflow = [Overflow.Visible, Overflow.Hidden, Overflow.Scroll][r(3)];
				case 9: s.visibility = [null, Visibility.Hidden, Visibility.Visible][r(3)];
				case 10: s.color = Color.rgb(r(0xffffff));
				case 11: s.position = r(3) == 0 ? Position.Sticky : Position.Relative;
				case 12: s.top = r(2) * 4;
				case _: s.padding = r(3) * 3;
			}
		}
		// (a tree, the same for the same seed: its nodes in the order made)
		function build(seed:Int, nodes:Array<Node>, moving:Array<Node>):Node {
			function r(n:Int):Int {
				seed = next(seed);
				return (seed >> 8) % n;
			}
			function make(depth:Int):Node {
				var k = r(depth >= 3 ? 3 : 8);
				var n = switch k {
					case 0: new TextNode(words[r(words.length)]);
					case 1: new ImageNode(img);
					case 2: new Stroked(line);
					case _: new Node();
				}
				n.style.background = Color.rgb(0x101010 * (1 + nodes.length % 15));
				nodes.push(n);
				// (a scroller of rows, a sticky one among them; a list under motion; a node moving every frame)
				if (k == 3) {
					n.style.overflow = Scroll;
					n.style.height = [60, 120][r(2)];
					for (i in 0...6 + r(10)) {
						var row = make(depth + 2);
						row.style.height = 18;
						if (r(6) == 0) {
							row.style.position = Sticky;
							row.style.top = 0;
						}
						n.append(row);
					}
				} else if (k == 4) n.motion = helder.ui.motion.MotionSpec.DEFAULT;
				else if (k == 5) moving.push(n);
				if (!n.hasContent() && k != 3)
					for (i in 0...r(4))
						n.append(make(depth + 1));
				for (i in 0...r(3))
					restyle(n, r);
				return n;
			}
			return make(0);
		}
		var t = Clock.now + 10;
		for (tree in 0...24) {
			var direct = new Ui(new MonoText(), 240, 200), layers = new Ui(new MonoText(), 240, 200);
			direct.direct = true;
			var uis = [direct, layers], all = [[], []], moving = [[], []];
			for (k in 0...2)
				uis[k].root.append(build(tree * 7919 + 3, all[k], moving[k]));
			var seed = tree * 104729 + 11, was = layers.recorded;
			function r(n:Int):Int {
				seed = next(seed);
				return (seed >> 8) % n;
			}
			for (frame in 0...30) {
				// (the moving nodes' transform and opacity, every frame)
				for (k in 0...2)
					for (i in 0...moving[k].length) {
						var n = moving[k][i], a = frame + i;
						n.style.transform = Transform.parse('translate(${a % 7}px, ${(a * 3) % 5}px)');
						n.style.opacity = 0.4 + (a % 5) / 10;
					}
				for (c in 0...r(3)) {
					var i = r(all[0].length), op = r(6), sub = r(1000000);
					for (k in 0...2) {
						var n = all[k][i], s = sub;
						function rs(m:Int):Int {
							s = next(s);
							return (s >> 8) % m;
						}
						if (n.ui == null) continue;
						switch op {
							case 0 if (Std.isOfType(n, TextNode)): (cast n : TextNode).text = words[rs(words.length)];
							case 1 if (!n.hasContent()):
								var c = new Node();
								c.style.set({width: 20 + rs(40), height: 10 + rs(20), background: Color.rgb(rs(0xffffff))});
								all[k].push(c);
								n.insert(c, rs(n.children.length + 1));
							case 2 if (n.parent != null && n.parent.parent != null): n.parent.remove(n);
							case 3 | 4 if (n.style.overflow == Scroll): uis[k].scrollTo(n, 0, rs(60));
							case 5 if (n.children.length > 0): n.remove(n.children[n.children.length - 1]);
							case _: restyle(n, rs);
						}
					}
				}
				t += 0.016;
				Clock.tick(t);
				var want = new Recording(), got = new Recording();
				direct.update();
				layers.update();
				direct.paint(want);
				layers.paint(got);
				frames++;
				if (want.calls.join("|") != got.calls.join("|")) {
					bad++;
					if (first == "") {
						var i = 0;
						while (i < want.calls.length && want.calls[i] == got.calls[i])
							i++;
						first = 'tree $tree frame $frame, call $i: ${want.calls[i]} against ${got.calls[i]}';
					}
				}
			}
			records += layers.recorded - was;
			copies += layers.copied;
		}
		check("layers: painted through them, as painted directly", bad == 0 && frames == 720, '$bad of $frames frames differ, first $first');
		check("layers: lists kept from frame to frame", records < frames * 3, '$records recorded in $frames frames');
		check("layers: what did not change in a layer recorded again copied from its last record", copies > frames, '$copies nodes copied in $frames frames');
	}

	// a frame that only scrolls a scroller recorded before, or only moves a
	// node's transform, records no layer: the scroller's content drawn at
	// its new offset, the node at its new transform
	static function layerRecords() {
		var ui = new Ui(new MonoText(), 200, 200), list = new Node(), card = new Node();
		list.style.set({overflow: Scroll, height: 150});
		for (i in 0...50) {
			var row = new TextNode("row " + i);
			row.style.height = 20;
			list.append(row);
		}
		card.style.set({width: 40, height: 20, background: 0xFF3366CC, position: Absolute, left: 100, top: 160});
		ui.root.append(card);
		ui.root.append(list);
		function frame():Int {
			var was = ui.recorded;
			ui.update();
			ui.paint(new Recording());
			return ui.recorded - was;
		}
		frame();
		check("layers: the first frame records the root and the scroller's content", ui.recorded == 2, ui.recorded + "");
		ui.scrollTo(list, 0, 30);
		check("layers: a scroll records nothing", frame() == 0);
		ui.scrollTo(list, 0, 140);
		check("layers: nor one within a viewport", frame() == 0);
		for (i in 0...3) {
			card.style.transform = Transform.parse('translate(${i * 4}px, 0)');
			frame();
		}
		card.style.transform = Transform.parse('translate(20px, 0)');
		check("layers: a moving transform records nothing", frame() == 0);
		card.style.opacity = 0.5;
		check("layers: nor its opacity", frame() == 0);
		// (hidden and shown again: its parent draws its layer again)
		card.style.display = None;
		ui.root.style.background = 0xFFF4F4F5;
		frame();
		card.style.display = Flex;
		ui.update();
		var want = new Recording(), got = new Recording();
		ui.direct = true;
		ui.paint(want);
		ui.direct = false;
		ui.paint(got);
		check("layers: a moving node shown again, drawn", want.calls.join("|") == got.calls.join("|"));
		(cast list.children[3] : TextNode).text = "changed";
		check("layers: a change in the scroller records its content alone", frame() == 1);
		// (its last row taken out: no other row moves, its content changed still)
		ui.scrollTo(list, 0, 0);
		while (list.children.length > 3)
			list.remove(list.children[3]);
		frame();
		list.remove(list.children[2]);
		ui.update();
		want = new Recording();
		got = new Recording();
		ui.direct = true;
		ui.paint(want);
		ui.direct = false;
		ui.paint(got);
		check("layers: a scroller's child taken out, its content recorded again", want.calls.join("|") == got.calls.join("|"));
	}

	// a node laid out again in place (Layout.inPlace: its parent's measures of
	// it as they were) placed as a layout from the root places it: random
	// trees changed at random (a text, a style, a child added or removed),
	// each frame's boxes against the same tree's laid out from scratch
	static function inPlace() {
		var seed = 1, bad = 0, steps = 0, first = "", was = Layout.inPlaces;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var words = ["a", "bb", "ccc dd", "eeee f gg", "hhhhhhh", "ii jj kk ll mm", "n"];
		var dims:Array<Dim> = [DimValue.Auto, 30, 70, "50%", "100%"];
		function restyle(n:Node):String {
			var s = n.style, k = rnd(26);
			switch k {
				case 0: s.width = dims[rnd(dims.length)];
				case 1: s.height = dims[rnd(dims.length)];
				case 2: s.flexDirection = [Direction.Row, Direction.Column, Direction.RowReverse][rnd(3)];
				case 3: s.flexWrap = rnd(2) == 0;
				case 4: s.flexGrow = rnd(3);
				case 5: s.flexShrink = rnd(2);
				case 6: s.padding = rnd(3) * 3;
				case 7: s.margin = rnd(3) * 2;
				case 8: s.alignItems = [Align.Stretch, Align.Start, Align.Center, Align.End, Align.Baseline][rnd(5)];
				case 9: s.alignSelf = [Align.Auto, Align.Start, Align.Baseline, Align.Stretch][rnd(4)];
				case 10: s.justifyContent = [Justify.Start, Justify.Center, Justify.SpaceBetween][rnd(3)];
				case 11: s.gap = rnd(3) * 4;
				case 12: s.minWidth = ([DimValue.Auto, 0, 40] : Array<Dim>)[rnd(3)];
				case 13: s.overflow = [Overflow.Visible, Overflow.Hidden, Overflow.Scroll][rnd(3)];
				case 14: s.flexBasis = ([DimValue.Auto, 0, 25] : Array<Dim>)[rnd(3)];
				case 15: s.display = rnd(5) == 0 ? Display.None : Display.Flex;
				case 16: s.fontSize = [8, 12, 20][rnd(3)];
				case 17:
					s.display = Display.Grid;
					s.gridTemplateColumns = Grid.tracks(["1fr auto", "40px 1fr", "repeat(3, 1fr)", "auto auto"][rnd(4)]);
				case 18: s.aspectRatio = [0, 1, 2][rnd(3)];
				case 19: s.boxShadow = rnd(2) == 0 ? null : Shadow.parse("0 4px 12px rgba(0,0,0,0.5)");
				case 20: s.transform = rnd(2) == 0 ? null : Transform.parse(["translate(30px, 10px)", "scale(1.5)", "translateX(-40px)"][rnd(3)]);
				// (inherited: what the texts below keep of them, again)
				case 21: s.direction = [null, Dir.Ltr, Dir.Rtl][rnd(3)];
				case 22: s.textTransform = [null, TextTransform.Uppercase, TextTransform.None][rnd(3)];
				case 23: s.textWrap = [null, TextWrap.Wrap, TextWrap.NoWrap, TextWrap.Balance][rnd(4)];
				case 24: s.letterSpacing = [null, 0.0, 2.0][rnd(3)];
				case _:
					s.position = rnd(4) == 0 ? Position.Absolute : Position.Relative;
					s.left = rnd(3) * 5;
					s.top = rnd(3) * 5;
			}
			return "style " + k;
		}
		var nodes:Array<Node> = [];
		function make(depth:Int):Node {
			var n = depth > 0 && rnd(3) == 0 || depth == 3 ? new TextNode(words[rnd(words.length)]) : new Node();
			// (each drawn: what the window culls by its ink)
			n.style.background = Color.rgb(0x101010 * (1 + nodes.length % 15));
			nodes.push(n);
			if (!Std.isOfType(n, TextNode))
				for (i in 0...rnd(4))
					n.append(make(depth + 1));
			for (i in 0...rnd(3))
				restyle(n);
			return n;
		}
		function boxes(n:Node, out:Array<Float>) {
			out.push(n.x);
			out.push(n.y);
			out.push(n.width);
			out.push(n.height);
			out.push(n.contentWidth);
			out.push(n.contentHeight);
			for (c in n.children)
				boxes(c, out);
		}
		// (the accessibility tree as text: each node's role, name and bounds, by id)
		function told(t:helder.ui.access.AccessTree):String {
			var ids = [for (id in t.nodes.keys()) id];
			ids.sort((a, b) -> a - b);
			return t.root + ";" + [for (id in ids) {
				var a = t.nodes.get(id);
				id + " " + a.role + " " + a.name + " " + [a.x, a.y, a.width, a.height].join(",") + " " + a.children.join(",");
			}].join("|");
		}
		function all(n:Node) {
			n.markDirty();
			for (c in n.children)
				all(c);
		}
		var drawn = 0, drawnFirst = "";
		for (tree in 0...40) {
			var ui = new Ui(new MonoText(), 240, 200);
			ui.root.style.alignItems = Start;
			nodes.resize(0);
			ui.root.append(make(0));
			ui.update();
			for (step in 0...60) {
				var n = nodes[rnd(nodes.length)], what;
				if (n.ui == null) continue;
				switch rnd(4) {
					case 0 if (Std.isOfType(n, TextNode)):
						(cast n : TextNode).text = words[rnd(words.length)];
						what = "text";
					case 1 if (!Std.isOfType(n, TextNode)):
						n.append(make(2));
						what = "added";
					case 2 if (n.parent != null && n.parent != ui.root):
						n.parent.remove(n);
						what = "removed";
					case _:
						what = restyle(n);
				}
				ui.update();
				var got = [], painted = new Recording();
				boxes(ui.root, got);
				ui.paint(painted);
				var tree = told(ui.accessTree());
				var points = [for (i in 0...12) [rnd(240), rnd(200)]], hit = [for (q in points) ui.root.hitTest(q[0], q[1])];
				all(ui.root);
				ui.update();
				var want = [], fresh = new Recording();
				boxes(ui.root, want);
				ui.paint(fresh);
				if (painted.calls.join("|") != fresh.calls.join("|") || tree != told(ui.accessTree()) || [for (i in 0...points.length) ui.root.hitTest(points[i][0], points[i][1]) == hit[i]].indexOf(false) >= 0) {
					drawn++;
					if (drawnFirst == "") drawnFirst = 'tree $tree step $step ($what on ${n.tag})';
				}
				steps++;
				if (got.join(",") != want.join(",")) {
					bad++;
					if (first == "") first = 'tree $tree step $step ($what on ${n.tag})';
				}
			}
		}
		// (what its parent reads besides its measures: its baseline, moved in a box of a fixed
		// size by the children above it; its min-content, a shrinking item's least width, its
		// text made shorter)
		function agrees(build:Ui->(Void->Void)):Bool {
			var ui = new Ui(new MonoText(), 240, 200);
			ui.root.style.alignItems = Start;
			var change = build(ui);
			ui.update();
			change();
			ui.update();
			var got = [];
			boxes(ui.root, got);
			all(ui.root);
			ui.update();
			var want = [];
			boxes(ui.root, want);
			return got.join(",") == want.join(",");
		}
		var baseline = agrees(ui -> {
			var row = new Node(), box = new Node(), above = new Node(), below = new Node();
			row.style.flexDirection = Row;
			row.style.alignItems = Baseline;
			box.style.width = 50;
			box.style.height = 80;
			above.style.height = 10;
			below.style.height = 30;
			box.append(above);
			box.append(new TextNode("b"));
			box.append(below);
			row.append(new TextNode("a"));
			row.append(box);
			ui.root.append(row);
			() -> {
				above.style.height = 30;
				below.style.height = 10;
			}
		});
		var least = agrees(ui -> {
			var row = new Node(), item = new Node(), text = new TextNode("aaaa");
			row.style.flexDirection = Row;
			row.style.width = 100;
			item.style.width = 60;
			item.append(text);
			var other = new Node();
			other.style.width = 80;
			other.style.minWidth = 80;
			row.append(item);
			row.append(other);
			ui.root.append(row);
			() -> text.text = "a";
		});
		check("in place: not when its baseline moved, nor its min-content changed", baseline && least, baseline + " " + least);
		// (a field typed into, of a width of its own, in a column of rows: it alone)
		var before = 0, after = 0;
		var typed = agrees(ui -> {
			var field = new TextField();
			field.style.width = 120;
			ui.root.append(field);
			for (i in 0...20)
				ui.root.append(new TextNode("row " + i));
			() -> {
				before = Layout.inPlaces;
				field.setText("typed");
				ui.update();
				after = Layout.inPlaces;
			}
		});
		// (Layout's own in-place layouts counted: on the engine, its caches instead, the layouts only compared)
		check("in place: a field typed into laid out alone", typed && #if !helder.layout true #else after == before + 1 #end, typed + " " + (after - before));
		var placed = Layout.inPlaces - was;
		check("in place: drawn, hit and told assistive technology as from the root, " + steps + " changes", drawn == 0, drawn + " differ, the first: " + drawnFirst);
		check("in place: as laid out from the root, " + steps + " changes (" + placed + " in place)", bad == 0 && #if !helder.layout true #else placed > steps / 4 #end,
			bad + " differ, the first: " + first + "; " + placed + " in place");
	}

	// a field edited at random (typing, an emoji of two UTF-16 units among
	// the letters, the arrows, Home and End with Shift or not, Backspace,
	// Delete, select all) against a string: its text, caret and anchor each
	// step; then undone back to empty and redone to the end
	static function editing() {
		var seed = 11, bad = 0, first = "";
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		for (round in 0...20) {
			var ui = new Ui(new MonoText(), 300, 100);
			var f = new TextField("");
			ui.root.append(f);
			ui.update();
			ui.setFocus(f);
			var text = "", caret = 0, anchor = 0;
			inline function low(i:Int):Bool
				return i >= 0 && i < text.length && StringTools.fastCodeAt(text, i) >= 0xDC00 && StringTools.fastCodeAt(text, i) <= 0xDFFF;
			function prev(i:Int):Int
				return i <= 0 ? 0 : low(i - 1) ? i - 2 : i - 1;
			function next(i:Int):Int
				return i >= text.length ? text.length : low(i + 1) ? i + 2 : i + 1;
			function over(s:String) {
				var a = caret < anchor ? caret : anchor, b = caret < anchor ? anchor : caret;
				text = text.substring(0, a) + s + text.substring(b);
				caret = anchor = a + s.length;
			}
			for (step in 0...60) {
				var what;
				switch rnd(9) {
					case 0 | 1 | 2:
						var c = rnd(8) == 0 ? 0x1F600 : rnd(5) == 0 ? 32 : "a".code + rnd(26);
						ui.keyDown(c, 0);
						ui.textInput(String.fromCharCode(c));
						over(String.fromCharCode(c));
						what = "typed";
					case 3:
						var shift = rnd(2) == 0;
						ui.keyDown(Key.LEFT, shift ? Mods.SHIFT : 0);
						caret = caret != anchor && !shift ? (caret < anchor ? caret : anchor) : prev(caret);
						if (!shift) anchor = caret;
						what = "left";
					case 4:
						var shift = rnd(2) == 0;
						ui.keyDown(Key.RIGHT, shift ? Mods.SHIFT : 0);
						caret = caret != anchor && !shift ? (caret < anchor ? anchor : caret) : next(caret);
						if (!shift) anchor = caret;
						what = "right";
					case 5:
						var shift = rnd(2) == 0, end = rnd(2) == 0;
						ui.keyDown(end ? Key.END : Key.HOME, shift ? Mods.SHIFT : 0);
						caret = end ? text.length : 0;
						if (!shift) anchor = caret;
						what = end ? "end" : "home";
					case 6:
						ui.keyDown(Key.BACKSPACE, 0);
						if (caret == anchor) anchor = prev(caret);
						over("");
						what = "backspace";
					case 7:
						ui.keyDown(Key.DELETE, 0);
						if (caret == anchor) anchor = next(caret);
						over("");
						what = "delete";
					case _:
						ui.keyDown("a".code, Mods.CONTROL);
						anchor = 0;
						caret = text.length;
						what = "select all";
				}
				ui.update();
				if (f.text != text || f.caret != caret || f.anchor != anchor) {
					bad++;
					if (first == "") first = 'round $round step $step ($what): "${f.text}" ${f.caret}/${f.anchor}, not "$text" $caret/$anchor';
					break;
				}
			}
			// (undone to the start, redone to the end)
			var end = f.text;
			for (i in 0...200)
				ui.keyDown("z".code, Mods.CONTROL);
			var undone = f.text;
			for (i in 0...200)
				ui.keyDown("z".code, Mods.CONTROL | Mods.SHIFT);
			if (undone != "" || f.text != end) {
				bad++;
				if (first == "") first = 'round $round: undone to "$undone", redone to "${f.text}", not "$end"';
			}
		}
		check("editing: a field edited at random as a string is", bad == 0, bad + " differ, the first: " + first);
	}

	// the theme's rules restyling what a change reaches (Rules: other nodes'
	// states, group, peer, has, prev, parent, first and last) as styling the
	// same tree from scratch does: random sheets and trees, attributes,
	// markers and children changed at random
	static function restyled() {
		var seed = 3, bad = 0, steps = 0, first = "";
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var conds = ["data-x", "data-y=1", "first", "last", "not:data-x", "group:data-x", "group/g:data-y=1", "peer:data-x", "peer/p:data-y=1", "has:data-x",
			"has:>data-slot=b", "has:data-x&data-y=1", "prev:data-x", "parent:data-y=1", "group:has:data-x", "not:has:data-y=1", "prev:data-slot=a"];
		var slots:Array<Null<String>> = ["a", "b", "c", null];
		var attrs = ["data-x", "data-y", "group", "peer"];
		function make(depth:Int, nodes:Array<Node>):Node {
			var n = new Node();
			n.slot = slots[rnd(slots.length)];
			for (a in attrs)
				if (rnd(4) == 0) n.setAttr(a, a == "data-y" ? "1" : a == "group" ? ["", "g"][rnd(2)] : a == "peer" ? ["", "p"][rnd(2)] : "");
			nodes.push(n);
			if (depth < 3)
				for (i in 0...rnd(4))
					n.append(make(depth + 1, nodes));
			return n;
		}
		function clone(n:Node):Node {
			var c = new Node();
			c.slot = n.slot;
			for (a in attrs)
				if (n.attr(a) != null) c.setAttr(a, n.attr(a));
			for (k in n.children)
				c.append(clone(k));
			return c;
		}
		function styles(n:Node, out:Array<Float>) {
			out.push(n.style.opacity);
			out.push(n.style.zIndex);
			for (c in n.children)
				styles(c, out);
		}
		for (round in 0...30) {
			var rules:Array<Rule> = [];
			for (i in 0...10) {
				var when = [conds[rnd(conds.length)]];
				if (rnd(3) == 0) when.push(conds[rnd(conds.length)]);
				var slot = ["a", "b", "c", "*"][rnd(4)];
				rules.push(rnd(2) == 0 ? {slot: slot, when: when, style: {opacity: (i + 1) / 20}} : {slot: slot, when: when, style: {zIndex: i + 1}});
			}
			var sheet:StyleSheet = {rules: rules};
			var ui = new Ui(new MonoText(), 200, 200);
			ui.theme = sheet;
			var nodes = [];
			var top = make(0, nodes);
			ui.root.append(top);
			ui.update();
			for (step in 0...40) {
				var n = nodes[rnd(nodes.length)], what;
				if (n.ui == null) continue;
				switch rnd(4) {
					case 0:
						var a = attrs[rnd(attrs.length)];
						n.setAttr(a, n.attr(a) != null ? null : a == "data-y" ? "1" : a == "group" ? "g" : a == "peer" ? "p" : "");
						what = "attr " + a;
					case 1:
						n.insert(make(2, nodes), rnd(n.children.length + 1));
						what = "inserted";
					case 2 if (n != top):
						n.parent.remove(n);
						what = "removed";
					case _:
						n.slot = slots[rnd(slots.length)];
						what = "slot";
				}
				ui.update();
				var got = [];
				styles(top, got);
				var fresh = new Ui(new MonoText(), 200, 200);
				fresh.theme = sheet;
				var copy = clone(top);
				fresh.root.append(copy);
				fresh.update();
				var want = [];
				styles(copy, want);
				steps++;
				if (got.join(",") != want.join(",")) {
					bad++;
					if (first == "") first = 'round $round step $step ($what)';
				}
			}
		}
		check("restyled: as styled from scratch, " + steps + " changes", bad == 0, bad + " differ, the first: " + first);
	}

	// an ancestor's decorations over a text: the underline before it, the
	// line-through after, both moved with its centred lines, in its colour
	static function decorations() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.fontSize = 10;
		var box = new Node("box");
		box.style.set({textDecoration: (TextDecoration.Underline : Int) | (TextDecoration.LineThrough : Int), color: Color.rgb(0xAA0000), textAlign: Center, width: 100});
		var t = new TextNode("abcd");
		t.style.color = Color.rgb(0x0000AA);
		box.append(t);
		ui.root.append(box);
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (StringTools.startsWith(c, "rect") || StringTools.startsWith(c, "text")) c.split(" ").slice(0, 6).join(" ")];
		// (MonoText at 10: 5 a character, lines 12.5 high; "abcd" 20 wide, centred in 100 at 40)
		var spaced = new TextNode("abcd");
		spaced.style.letterSpacing = 1;
		ui.root.append(spaced);
		ui.update();
		check("letter spacing: in the text's font", spaced.laidOut() != null && spaced.laidOut().width == 24 && spaced.font().letterSpacing == 1, spaced.laidOut() == null ? "none" : "" + spaced.laidOut().width);
		ui.root.remove(spaced);
		var just = new TextNode("one two three four five six");
		just.style.set({width: 60, textAlign: Justify});
		ui.root.append(just);
		ui.update();
		var jp:MonoText.MonoParagraph = cast just.laidOut();
		var asked = jp != null && jp.justified;
		just.style.textAlign = Left;
		ui.update();
		jp = cast just.laidOut();
		check("justify: asked of the engine, laid out again when it changes", asked && jp != null && !jp.justified);
		ui.root.remove(just);
		ui.update();
		check("decorations: an ancestor's, around the text, aligned, in its colour",
			calls.join("|") == "rect 40 11.25 20 1 0|text 0 0 100|rect 40 6.25 20 1 0" && rec.calls.filter(c -> c.indexOf("ffaa0000") >= 0).length == 2, calls.join("|"));
	}

	// selectable text: a drag, a double click, a triple, copied, dropped
	static function selection() {
		var ui = new Ui(new MonoText(), 300, 100);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var t = new TextNode("hello world foo");
		t.selectable = true;
		ui.root.append(t);
		var other = new Node("other");
		other.style.set({width: 50, height: 20});
		ui.root.append(other);
		ui.update();
		var time = 0.0;
		Ui.now = () -> time;
		// (MonoText at 10: 5 pixels a character, the line 12.5 high)
		ui.pointerDown(t.absX + 1, t.absY + 5, 1);
		ui.pointerMove(t.absX + 26, t.absY + 5);
		ui.pointerUp(t.absX + 26, t.absY + 5, 1);
		check("selection: a drag selects", ui.selectedText() == "hello" && t.style.cursor == Text, ui.selectedText());
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (StringTools.startsWith(c, "rect") || StringTools.startsWith(c, "text")) c.split(" ").slice(0, 5).join(" ")];
		check("selection: painted under the text", calls.join("|") == "rect 0 0 25 12.5|text 0 0 75", calls.join("|"));
		ui.keyDown("c".code, Mods.CONTROL);
		var copied:Null<String> = null;
		ui.clipboard.read(s -> copied = s);
		check("selection: Control+C copies it", copied == "hello", copied);
		time = 10;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		time = 10.2;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		check("selection: a double click, the word", ui.selectedText() == "world", ui.selectedText());
		time = 10.4;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		check("selection: a triple click, all of it", ui.selectedText() == "hello world foo", ui.selectedText());
		time = 20;
		ui.pointerDown(other.absX + 5, other.absY + 5, 1);
		check("selection: a press elsewhere drops it", ui.textSelection == null);
		// (user-select: none on it, not selected; all, all of it at a click; text on an ancestor, a text of its own flag unset)
		t.style.userSelect = None;
		time = 30;
		ui.pointerDown(t.absX + 3, t.absY + 5, 1);
		ui.pointerUp(t.absX + 3, t.absY + 5, 1);
		var none = ui.textSelection == null;
		t.style.userSelect = All;
		time = 40;
		ui.pointerDown(t.absX + 3, t.absY + 5, 1);
		ui.pointerUp(t.absX + 3, t.absY + 5, 1);
		var all = ui.selectedText();
		t.style.userSelect = null;
		t.selectable = false;
		ui.root.style.userSelect = Text;
		time = 50;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		time = 50.2;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		check("selection: user-select none, all, text inherited", none && all == "hello world foo" && ui.selectedText() == "world", all + " " + ui.selectedText());
		ui.root.style.userSelect = null;
		t.selectable = true;
		time = 60;
		ui.pointerDown(other.absX + 5, other.absY + 5, 1);
		// (centred in 300: the line of 75 starts at 112.5)
		t.style.width = 300;
		t.style.textAlign = Center;
		ui.update();
		time = 30;
		ui.pointerDown(t.absX + 113, t.absY + 5, 1);
		ui.pointerMove(t.absX + 113 + 25, t.absY + 5);
		ui.pointerUp(t.absX + 113 + 25, t.absY + 5, 1);
		check("selection: on a centred line", ui.selectedText() == "hello", ui.selectedText());
		Ui.now = haxe.Timer.stamp;
	}

	// --- shortcuts ---

	// (a keymap's keystrokes: their keys, their labels; the keymap itself is Actions.test.hx's)
	static function shortcuts() {
		var s = Keystroke.parse("secondary-shift-s");
		check("shortcuts: secondary as Control, Shift's capital", s.matches("s".code, Mods.CONTROL | Mods.SHIFT) && s.matches("S".code, Mods.CONTROL | Mods.SHIFT)
			&& !s.matches("s".code, Mods.CONTROL) && !s.matches("s".code, Mods.META | Mods.SHIFT) && !s.matches("s".code, Mods.SHIFT));
		check("shortcuts: keys by name", Keystroke.parse("f5").matches(0xFFC2, 0) && Keystroke.parse("ctrl-pagedown").matches(Key.PAGE_DOWN, Mods.CONTROL)
			&& Keystroke.parse("ctrl-+").matches("+".code, Mods.CONTROL) && Keystroke.parse("alt-Enter").matches(Key.ENTER, Mods.ALT));
		var labels = [s.label(), Keystroke.parse("alt-f4").label(), Keystroke.parse("escape").label()].join(" ");
		Keymap.mac = true;
		var mac = [s.label(), Keystroke.parse("ctrl-alt-delete").label(), Keystroke.parse("secondary-enter").label()].join(" ");
		Keymap.mac = false;
		check("shortcuts: labels", labels == "Ctrl+Shift+S Alt+F4 Esc" && mac == "⇧⌘S ⌃⌥⌦ ⌘↩", labels + " / " + mac);
		var bad = 0;
		for (t in ["hyper-s", "ctrl-", "ctrl-nope", "f99"])
			try Keystroke.parse(t) catch (_:Dynamic) bad++;
		check("shortcuts: what is not one throws", bad == 4, '$bad');
	}

	// --- popups ---

	static function popups() {
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.alignItems = Start;
		ui.root.style.padding = 10;
		var clip = new Node("clip");
		clip.style.set({width: 100, height: 30, overflow: Hidden});
		var button = new Node("button");
		button.style.set({width: 60, height: 20});
		button.focusable = true;
		clip.append(button);
		ui.root.append(clip);
		var p = new Popup("menu");
		p.anchor = button;
		p.style.set({width: 80, height: 50, background: Color.WHITE});
		var item = new Node("item");
		item.style.set({width: 80, height: 20});
		item.focusable = true;
		p.append(item);
		var dismissed = 0;
		p.onDismiss = () -> dismissed++;
		ui.update();
		ui.open(p);
		ui.update();
		check("popups: below the anchor, out of its clip", p.absX == 10 && p.absY == 34 && p.parent == ui.overlay, '${p.absX},${p.absY}');
		check("popups: hit over the tree", @:privateAccess ui.hit(15, 40) == item && @:privateAccess ui.hit(15, 15) == button);
		var rec = new Recording();
		ui.paint(rec);
		check("popups: drawn after the tree", rec.calls[rec.calls.length - 1].indexOf("80 50") >= 0, rec.calls.join("|"));
		var at = ui.accessTree();
		check("popups: in the accessibility tree", at.order.length > 0 && at.node(at.order[at.order.length - 1]) == item || [for (id in at.order) at.node(id)].contains(item));
		// flipped above near the bottom, kept inside on the right
		clip.style.set({margin: [150.0, 0, 0, 250]});
		ui.update();
		check("popups: flipped above, kept in the window", p.absY == 160 - 4 - 50 && p.absX == 300 - 80, '${p.absX},${p.absY}');
		// right to left: the anchor's right edge and the popup's lined up
		clip.style.set({margin: [0.0, 0, 0, 100]});
		ui.root.style.direction = Rtl;
		ui.update();
		var anchorRight = button.absX + button.width;
		check("popups: right to left, their right edges lined up", p.absX + p.width == anchorRight, '${p.absX + p.width} ${anchorRight}');
		ui.root.style.direction = null;
		// at a point: there, flipped left and up where it does not fit
		p.placement = Point;
		p.atX = 20;
		p.atY = 30;
		ui.update();
		var there = p.absX == 20 && p.absY == 30;
		p.atX = 290;
		p.atY = 190;
		ui.update();
		check("popups: at a point, flipped where it does not fit", there && p.absX == 290 - 80 && p.absY == 190 - 50, '${p.absX},${p.absY}');
		p.placement = Below;
		ui.update();
		// dismissed by a press outside, not on the anchor or inside
		ui.pointerDown(p.absX + 5, p.absY + 5, 1);
		ui.pointerUp(p.absX + 5, p.absY + 5, 1);
		ui.pointerDown(button.absX + 5, button.absY + 5, 1);
		ui.pointerUp(button.absX + 5, button.absY + 5, 1);
		check("popups: not dismissed inside or on the anchor", dismissed == 0, '$dismissed');
		ui.pointerDown(5, 5, 1);
		ui.pointerUp(5, 5, 1);
		check("popups: dismissed by a press outside", dismissed == 1, '$dismissed');
		ui.keyDown(Key.ESCAPE, 0);
		check("popups: dismissed by Escape", dismissed == 2, '$dismissed');
		ui.close(p);
		ui.update();
		check("popups: closed", p.parent == null && ui.overlay.children.length == 0);
		// a modal dialog: the focus inside, Tab cycling in it, the tree covered
		ui.setFocus(button);
		var d = new Popup("dialog");
		d.modal = true;
		var box = new Node("box");
		box.style.set({width: 120, height: 60});
		var a = new Node("a"), b = new Node("b");
		for (n in [a, b]) {
			n.style.set({width: 40, height: 20});
			n.focusable = true;
			box.append(n);
		}
		d.append(box);
		var closed = 0;
		d.onDismiss = () -> closed++;
		ui.open(d);
		ui.update();
		check("popups: a modal covers the window, its content centred", d.width == 300 && d.height == 200 && box.absX == 90 && box.absY == 70, '${d.width}x${d.height} ${box.absX},${box.absY}');
		check("popups: a modal takes the focus", ui.focus == a);
		ui.keyDown(Key.TAB, 0);
		ui.keyDown(Key.TAB, 0);
		check("popups: Tab cycles inside it", ui.focus == a, '${ui.focus}');
		check("popups: the tree under it covered", @:privateAccess ui.hit(button.absX + 2, button.absY + 2) == d);
		ui.pointerDown(box.absX + 2, box.absY + 2, 1);
		ui.pointerUp(box.absX + 2, box.absY + 2, 1);
		ui.pointerDown(2, 2, 1);
		ui.pointerUp(2, 2, 1);
		check("popups: its backdrop dismisses it, its content does not", closed == 1, '$closed');
		ui.close(d);
		check("popups: closing gives the focus back", ui.focus == button, '${ui.focus}');
	}

	// --- fields ---

	static function fields() {
		var ui = new Ui(new MonoText(), 300, 100);
		var f = new TextField("");
		var changes = 0;
		f.onChange = _ -> changes++;
		ui.root.append(f);
		ui.update();
		ui.setFocus(f);
		function type(t:String)
			for (c in new haxe.iterators.StringIteratorUnicode(t)) {
				ui.keyDown(c, 0);
				ui.textInput(String.fromCharCode(c));
			}
		function key(k:Int, mods = 0)
			ui.keyDown(k, mods);
		type("hello world");
		check("fields: typing", f.text == "hello world" && f.caret == 11 && changes == 11, f.text);
		key(Key.LEFT, Mods.SHIFT);
		key(Key.LEFT, Mods.SHIFT);
		key(Key.LEFT, Mods.SHIFT);
		key(Key.LEFT, Mods.SHIFT);
		key(Key.LEFT, Mods.SHIFT);
		key("c".code, Mods.CONTROL);
		var clip:ClipboardHost.MemoryClipboard = cast ui.clipboard;
		check("fields: copy", clip.text == "world" && f.text == "hello world", clip.text);
		key("x".code, Mods.CONTROL);
		check("fields: cut", clip.text == "world" && f.text == "hello " && f.caret == 6, f.text);
		key(Key.HOME);
		key("v".code, Mods.META);
		check("fields: paste (Command too)", f.text == "worldhello " && f.caret == 5, f.text);
		clip.text = "two\nlines\r\nhere";
		key("a".code, Mods.CONTROL);
		key("v".code, Mods.CONTROL);
		check("fields: a paste over the selection, on one line", f.text == "two lines here", f.text);
		key(Key.BACKSPACE);
		key(Key.BACKSPACE);
		key(Key.BACKSPACE);
		key(Key.BACKSPACE);
		check("fields: Backspace", f.text == "two lines ", f.text);
		key("c".code, Mods.CONTROL);
		check("fields: copy without a selection leaves the clipboard", clip.text == "two\nlines\r\nhere");
		// a clipboard that answers later
		var lc = new LaterClipboard();
		var later = lc.waiting;
		ui.clipboard = lc;
		key("v".code, Mods.CONTROL);
		check("fields: a paste waits for the text", f.text == "two lines " && later.length == 1);
		later[0]("later");
		check("fields: then types it", f.text == "two lines later", f.text);
		// words, undo and redo, clicks in a row
		var ui = new Ui(new MonoText(), 300, 100);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var h = new TextField("");
		h.style.width = 200;
		ui.root.append(h);
		ui.update();
		ui.setFocus(h);
		function typeH(t:String)
			for (c in new haxe.iterators.StringIteratorUnicode(t))
				ui.textInput(String.fromCharCode(c));
		typeH("hello big world");
		ui.keyDown(Key.LEFT, Mods.CONTROL);
		check("words: Control+Left to the word's start", h.caret == 10, '${h.caret}');
		ui.keyDown(Key.LEFT, Mods.ALT);
		check("words: Alt+Left (Option) too", h.caret == 6, '${h.caret}');
		ui.keyDown(Key.RIGHT, Mods.CONTROL | Mods.SHIFT);
		check("words: Shift selects to the word's end", h.selectionStart == 6 && h.selectionEnd == 9, '${h.selectionStart}-${h.selectionEnd}');
		ui.keyDown(Key.END, 0);
		ui.keyDown(Key.BACKSPACE, Mods.CONTROL);
		check("words: Control+Backspace deletes a word", h.text == "hello big ", h.text);
		ui.keyDown(Key.LEFT, Mods.META);
		check("words: Command+Left to the start", h.caret == 0);
		check("undo: a word deleted, undone", { ui.keyDown("z".code, Mods.CONTROL); h.text == "hello big world"; }, h.text);
		ui.keyDown("z".code, Mods.META);
		check("undo: typing undone as runs (words apart)", h.text == "hello big ", h.text);
		ui.keyDown("z".code, Mods.CONTROL | Mods.SHIFT);
		check("redo: Control+Shift+Z", h.text == "hello big world", h.text);
		ui.keyDown("y".code, Mods.CONTROL);
		check("redo: Control+Y", h.text == "hello big ", h.text);
		for (_ in 0...10)
			ui.keyDown("z".code, Mods.CONTROL);
		check("undo: back to empty", h.text == "", h.text);
		ui.keyDown("y".code, Mods.CONTROL);
		typeH("x");
		ui.keyDown("y".code, Mods.CONTROL);
		check("redo: an edit clears what was undone", StringTools.endsWith(h.text, "x"), h.text);
		h.setText("one two three");
		ui.update();
		ui.paint(new Recording());
		var t = 0.0;
		EditableText.now = () -> t;
		var cx = h.absX + h.style.borderWidth + h.style.padding.left + 5.5 * 5; // (within "two")
		var cy = h.absY + h.height / 2;
		function clickH(x:Float, at:Float, mods = 0) {
			t = at;
			if (mods != 0) ui.keyDown(Key.SHIFT, mods);
			ui.pointerDown(x, cy, 1);
			ui.pointerUp(x, cy, 1);
			if (mods != 0) ui.keyUp(Key.SHIFT, 0);
		}
		clickH(cx, 10);
		clickH(cx, 10.2);
		check("clicks: a double click selects a word", h.selectionStart == 4 && h.selectionEnd == 7, '${h.selectionStart}-${h.selectionEnd}');
		clickH(cx, 10.4);
		check("clicks: a triple click the line", h.selectionStart == 0 && h.selectionEnd == 13, '${h.selectionStart}-${h.selectionEnd}');
		clickH(cx, 20);
		clickH(h.absX + h.style.borderWidth + h.style.padding.left + 1, 30, Mods.SHIFT);
		check("clicks: Shift+click extends the selection", h.selectionStart == 0 && h.selectionEnd == 6, '${h.selectionStart}-${h.selectionEnd}');
		EditableText.now = haxe.Timer.stamp;
		// the focus moved by Tab: its node scrolled into view; a press does not scroll
		var sui = new Ui(new MonoText(), 200, 100);
		var box = new Node("scroller");
		box.style.overflow = Scroll;
		box.style.height = 60;
		box.style.padding = 5;
		sui.root.append(box);
		var rows = [for (i in 0...10) {
			var r = new Node("row" + i);
			r.style.height = 20;
			// (as in CSS: an empty box of a fixed height shrinks in a column it overflows)
			r.style.flexShrink = 0;
			r.focusable = true;
			box.append(r);
			r;
		}];
		sui.update();
		sui.setFocus(rows[0]);
		for (_ in 0...4)
			sui.keyDown(Key.TAB, 0);
		check("focus: Tab scrolls the focused row into view", sui.focus == rows[4] && box.scrollY == 4 * 20 + 20 - 50, '${box.scrollY}');
		sui.keyDown(Key.TAB, Mods.SHIFT);
		sui.keyDown(Key.TAB, Mods.SHIFT);
		sui.keyDown(Key.TAB, Mods.SHIFT);
		check("focus: and back up", sui.focus == rows[1] && box.scrollY == 20, '${box.scrollY}');
		// grapheme clusters: a letter and its marks, an emoji with its modifier, a flag move as one; Backspace takes a mark at a time
		var q = "e\u0301\u{1F44D}\u{1F3FD}\u{1F1E7}\u{1F1EA}";
		var units = "\u{1F600}".length;
		h.setText(q);
		h.select(0, 0);
		var steps = [];
		for (_ in 0...4) {
			ui.keyDown(Key.RIGHT, 0);
			steps.push(h.caret);
		}
		check("graphemes: Right steps over clusters", steps.join(",") == [2, 2 + 2 * units, 2 + 4 * units, 2 + 4 * units].join(","), steps.join(","));
		ui.keyDown(Key.LEFT, 0);
		check("graphemes: Left too", h.caret == 2 + 2 * units, '${h.caret}');
		h.select(2, 2);
		ui.keyDown(Key.BACKSPACE, 0);
		check("graphemes: Backspace takes a mark", h.text == "e\u{1F44D}\u{1F3FD}\u{1F1E7}\u{1F1EA}" && h.caret == 1, h.text);
		h.select(1 + 2 * units, 1 + 2 * units);
		ui.keyDown(Key.BACKSPACE, 0);
		check("graphemes: Backspace takes an emoji with its modifier", h.text == "e\u{1F1E7}\u{1F1EA}", h.text);
		h.select(1, 1);
		ui.keyDown(Key.DELETE, 0);
		check("graphemes: Delete takes a flag", h.text == "e", h.text);
		// Left and Right in right-to-left text move the caret as it looks (real fonts: DrawText, with DejaVu Sans)
		var dejavu = helder.text.SystemFonts.get().match("DejaVu Sans");
		if (dejavu != null && dejavu.family == "DejaVu Sans") {
			var rui = new Ui(helder.ui.TextEngines.standard(), 300, 100);
			rui.root.style.fontFamily = "DejaVu Sans";
			rui.root.style.alignItems = Start;
			var r = new TextField("ab \u05D0\u05D1\u05D2");
			r.style.width = 200;
			rui.root.append(r);
			rui.update();
			rui.setFocus(r);
			r.select(2, 2);
			var seq = [];
			for (_ in 0...5) {
				rui.keyDown(Key.RIGHT, 0);
				seq.push(r.caret);
			}
			check("bidi: Right goes rightward through Hebrew, then stays", seq.join(",") == "6,5,4,3,3", seq.join(","));
			r.setText("\u05D0\u05D1\u05D2");
			r.select(0, 0);
			var back = [];
			for (_ in 0...4) {
				rui.keyDown(Key.LEFT, 0);
				back.push(r.caret);
			}
			rui.keyDown(Key.RIGHT, 0);
			check("bidi: Left in Hebrew goes forward, Right back", back.join(",") == "1,2,3,3" && r.caret == 2, back.join(",") + " " + r.caret);
		}
		// an input method's composition: shown at the caret, underlined, typed when committed
		var ui = new Ui(new MonoText(), 300, 100);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var g = new TextField("ab");
		g.style.width = 100;
		var gc = 0;
		g.onChange = _ -> gc++;
		ui.root.append(g);
		ui.update();
		ui.paint(new Recording());
		check("composition: no text input without the focus", ui.textInputArea() == null);
		ui.setFocus(g);
		ui.update();
		ui.paint(new Recording());
		var at = ui.textInputArea();
		check("composition: the caret's area", at != null && at.height == 12.5 && at.width == 1, '$at');
		var x0 = at == null ? 0.0 : at.x;
		g.select(1, 2);
		ui.composition("にほん", 3);
		check("composition: the selection goes, the text waits", g.text == "a" && g.composition == "にほん" && gc == 1, g.text + "|" + g.composition);
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		check("composition: drawn in the text", rec.calls.filter(s -> StringTools.startsWith(s, "text")).map(s -> s.split(" ")[3]).join(",") == "20", rec.calls.join("|"));
		check("composition: underlined", rec.calls.filter(s -> StringTools.startsWith(s, "rect") && s.split(" ")[3] == "15" && s.split(" ")[4] == "1").length == 1, rec.calls.join("|"));
		at = ui.textInputArea();
		check("composition: the caret in it", at != null && at.x == x0 - 5 + 15, '$at $x0');
		ui.composition("日本", 1);
		ui.update();
		ui.paint(new Recording());
		at = ui.textInputArea();
		check("composition: its caret moves", at != null && at.x == x0 - 5 + 5 && g.text == "a", '$at');
		ui.composition("", 0);
		ui.textInput("日本");
		check("composition: committed", g.text == "a日本" && g.composition == "" && g.caret == 3 && gc == 2, g.text);
		ui.composition("x", 1);
		ui.setFocus(null);
		check("composition: dropped on blur", g.composition == "" && g.text == "a日本" && ui.textInputArea() == null);
		spelling();
		// a text area: 100 wide, 20 characters a line (MonoText at 10: 5 each, lines of 12.5)
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var a = new TextArea("");
		a.style.width = 100;
		a.rows = 2;
		ui.root.append(a);
		ui.update();
		check("area: rows high", a.height == 25 && a.width == 100, '${a.width}x${a.height}');
		// (sized by its text: a line empty, then three, over a minimum height)
		var grown = new TextArea("");
		grown.style.width = 100;
		grown.style.fieldSizing = Content;
		ui.root.append(grown);
		ui.update();
		var empty = grown.height;
		grown.setText("a\nb\nc");
		ui.update();
		var three = grown.height;
		grown.style.minHeight = 64;
		ui.update();
		check("area: field-sizing content, as tall as its lines; a minimum over it", empty == 13 && three == 38 && grown.height == 64,
			empty + " " + three + " " + grown.height);
		ui.root.remove(grown);
		ui.setFocus(a);
		function typeIn(t:String)
			for (c in new haxe.iterators.StringIteratorUnicode(t)) {
				ui.keyDown(c, 0);
				ui.textInput(String.fromCharCode(c));
			}
		typeIn("first line");
		ui.keyDown(Key.ENTER, 0);
		typeIn("second");
		check("area: Enter types a line", a.text == "first line\nsecond" && a.caret == 17, a.text);
		ui.keyDown(Key.UP, 0);
		check("area: Up keeps the column", a.caret == 6, '${a.caret}');
		ui.keyDown(Key.END, 0);
		check("area: End of the line", a.caret == 10, '${a.caret}');
		ui.keyDown(Key.DOWN, 0);
		check("area: Down to a shorter line: its end", a.caret == 17, '${a.caret}');
		ui.keyDown(Key.HOME, 0);
		check("area: Home of the line", a.caret == 11, '${a.caret}');
		ui.keyDown(Key.UP, Mods.SHIFT);
		check("area: Shift+Up selects", a.selectionStart == 0 && a.selectionEnd == 11, '${a.selectionStart}-${a.selectionEnd}');
		ui.keyDown(Key.END, Mods.CONTROL);
		typeIn(" and a third line that wraps");
		ui.update();
		var c = new Recording();
		ui.paint(c);
		check("area: wrapped and scrolled to the caret (three lines in two)", c.calls.filter(s -> StringTools.startsWith(s, "text")).join("") == "text 0 -12.5 100", c.calls.join("|"));
		var clip:ClipboardHost.MemoryClipboard = cast ui.clipboard;
		clip.text = "x\ny";
		ui.keyDown("v".code, Mods.CONTROL);
		check("area: a paste keeps its lines", StringTools.endsWith(a.text, "wrapsx\ny"), a.text);
	}

	// --- images ---

	static function images() {
		// ImageNode: its size from the image's, its placement by fit
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.alignItems = Start;
		var img = new Image(40, 20);
		var natural = new ImageNode(img), wide = new ImageNode(img), box = new ImageNode(img);
		wide.style.width = 100;
		box.style.set({width: 100, height: 100, borderRadius: 12});
		for (n in [natural, wide, box])
			ui.root.append(n);
		ui.update();
		check("images: the natural size", natural.width == 40 && natural.height == 20, '${natural.width}x${natural.height}');
		check("images: the aspect ratio kept", wide.width == 100 && wide.height == 50, '${wide.width}x${wide.height}');
		// (aspect-ratio given: it, not the image's, in a column's item and through its automatic minimum)
		var col = new Ui(new MonoText(), 300, 600);
		var framed = new ImageNode(new Image(40, 70));
		framed.style.aspectRatio = 0.75;
		col.root.append(framed);
		col.update();
		check("images: a given aspect ratio over the image's", framed.width == 300 && framed.height == 400, '${framed.width}x${framed.height}');
		check("images: Fill", box.placement(0, 0, 100, 100).join(",") == "0,0,100,100,0,0,1,1");
		box.fit = Contain;
		check("images: Contain", box.placement(0, 0, 100, 100).join(",") == "0,25,100,50,0,0,1,1", box.placement(0, 0, 100, 100).join(","));
		box.fit = Cover;
		check("images: Cover", box.placement(0, 0, 100, 100).join(",") == "0,0,100,100,0.25,0,0.75,1", box.placement(0, 0, 100, 100).join(","));
		box.fit = ImageFit.None;
		check("images: None", box.placement(0, 0, 100, 100).join(",") == "30,40,40,20,0,0,1,1", box.placement(0, 0, 100, 100).join(","));
		// object-position: a share of the room left over and pixels more, the part outside cut
		function placed(fit:ImageFit, pos:String):String {
			box.fit = fit;
			box.position(pos);
			return box.placement(0, 0, 100, 100).join(",");
		}
		var got = [
			placed(Contain, "left top"), placed(Contain, "bottom"), placed(Cover, "right"), placed(Cover, "25% 0"), placed(ImageFit.None, "right 10px bottom 5px"),
			placed(ImageFit.None, "-30px 10px"), placed(ImageFit.None, "center top")
		];
		var want = [
			"0,0,100,50,0,0,1,1", "0,50,100,50,0,0,1,1", "0,0,100,100,0.5,0,1,1", "0,0,100,100,0.125,0,0.625,1", "50,75,40,20,0,0,1,1",
			"0,10,10,20,0.75,0,1,1", "30,0,40,20,0,0,1,1"
		];
		check("images: object-position", got.join("|") == want.join("|"), got.join("|"));
		var badPosition = try {
			box.position("sideways");
			false;
		} catch (e:Dynamic) true;
		box.position("center");
		check("images: object-position rejects what CSS does not write", badPosition && box.positionX == 0.5 && box.positionY == 0.5);
		var c = new Recording();
		ui.paint(c);
		check("images: painted", c.calls.join("|") == "image 40x20 0 0 40 20 0 0 1 1 0|image 40x20 0 20 100 50 0 0 1 1 0|image 40x20 30 110 40 20 0 0 1 1 12", c.calls.join("|"));
	}

	// --- themes: rules by slot, variant, size and state; tokens; the node's own style ---

static function transitions() {
		// parsed as CSS writes them; CSS's easings
		var t = Transition.parse("background-color 150ms ease-in-out, opacity 0.2s 50ms, box-shadow 1s cubic-bezier(0.4, 0, 0.2, 1)");
		check("transitions: parsed", t.properties.join(",") == "background,opacity,boxShadow" && t.durations.join(",") == "0.15,0.2,1"
			&& t.delays.join(",") == "0,0.05,0" && t.easings[0] == Transition.EASE_IN_OUT && t.easings[2].join(",") == "0.4,0,0.2,1"
			&& t.timing("color") == null && Transition.parse("all 1s").timing("borderColor").duration == 1 && Transition.parse("none") == null,
			t.properties.join(","));
		check("transitions: ease's curve as CSS's", Math.abs(Transition.ease(Transition.EASE, 0.5) - 0.8024) < 1e-3
			&& Math.abs(Transition.ease(Transition.LINEAR, 0.3) - 0.3) < 1e-6 && Math.abs(Transition.ease(Transition.EASE_IN_OUT, 0.5) - 0.5) < 1e-6,
			"" + Transition.ease(Transition.EASE, 0.5));
		check("transitions: colours with their alphas premultiplied", Color.between(Color.TRANSPARENT, Color.rgb(0xFF0000), 0.5) == Color.rgba(0xFF0000, 0.5)
			&& Color.between(Color.rgb(0x000000), Color.rgb(0xFFFFFF), 0.5) == Color.rgb(0x808080));
		var tr = Transform.between(null, Transform.parse("translateX(14px)"), 0.5).toString();
		var sh = Shadow.between(null, Shadow.parse("0 4px 8px #00000080"), 0.5);
		check("transitions: a transform from none, a shadow from none", tr == "translatex(7)" && sh.y == 2 && sh.blur == 4 && sh.color.a == 64,
			tr + " " + sh.y + " " + sh.blur + " " + sh.color.a);
		// a node's change, once drawn, eases on the Clock; the target known
		var ui = new Ui(new MonoText(), 100, 100);
		var n = new Node("n");
		n.style.set({width: 20, height: 20, background: Color.rgb(0x000000), transition: Transition.parse("background-color 100ms linear")});
		ui.root.append(n);
		n.style.background = Color.rgb(0x0000FF);
		check("transitions: not drawn yet, a change jumps", n.style.background == Color.rgb(0x0000FF));
		ui.update();
		ui.paint(new Recording());
		Clock.tick(10);
		n.style.background = Color.rgb(0xFFFFFF);
		check("transitions: drawn, a change starts where it is", n.style.background == Color.rgb(0x0000FF) && n.style.target("background") == Color.rgb(0xFFFFFF)
			&& Clock.active);
		Clock.tick(10.5);
		Clock.tick(10.55);
		var mid = n.style.background;
		Clock.tick(10.61);
		check("transitions: halfway, then there", Math.abs(mid.r - 0x80) <= 1 && mid.b == 0xFF && n.style.background == Color.rgb(0xFFFFFF) && !Clock.active, mid.toHex());
		// (set back mid-way: from where it is; the same value again: the run stopped)
		n.style.background = Color.rgb(0x000000);
		Clock.tick(20);
		Clock.tick(20.05);
		n.style.background = Color.rgb(0xFFFFFF);
		var from = n.style.background;
		Clock.tick(20.06);
		Clock.tick(20.11);
		check("transitions: turned back from where it was", Math.abs(from.r - 0x80) <= 1 && n.style.background.r > 0x80 && n.style.background.r < 0xFF,
			from.toHex() + " " + n.style.background.toHex());
		Clock.finish();
		// a theme's rules: a hover's colour eased, the rules still the node's own's judge
		var sheet:StyleSheet = {rules: [
			{slot: "b", style: {background: Color.rgb(0x000000), transition: Transition.parse("background-color 150ms linear")}},
			{slot: "b", when: ["hover"], style: {background: Color.rgb(0xFFFFFF)}}
		]};
		ui.theme = sheet;
		var b = new Node("b");
		b.slot = "b";
		b.style.set({width: 20, height: 20});
		ui.root.append(b);
		ui.update();
		ui.paint(new Recording());
		check("transitions: a theme's first style jumps", b.style.background == Color.rgb(0x000000));
		ui.pointerMove(b.absX + 5, b.absY + 5);
		ui.update();
		check("transitions: the hover's colour eases", b.style.background == Color.rgb(0x000000) && b.style.target("background") == Color.rgb(0xFFFFFF));
		Clock.finish();
		ui.pointerMove(90, 90);
		ui.update();
		Clock.finish();
		check("transitions: and back, the rules' all along", b.style.background == Color.rgb(0x000000), b.style.background.toHex());
		// (starting rules, as CSS's @starting-style: before the first draw; then eased from)
		ui.theme = {rules: [
			{slot: "pop", style: {opacity: 1, transition: Transition.parse("opacity 100ms linear")}},
			{slot: "pop", when: ["starting"], style: {opacity: 0}}
		]};
		var pop = new Node("pop");
		pop.slot = "pop";
		pop.style.set({width: 10, height: 10});
		ui.root.append(pop);
		ui.update();
		var first = pop.style.opacity;
		ui.paint(new Recording());
		ui.update();
		Clock.tick(200);
		Clock.tick(200.05);
		var mid = pop.style.opacity;
		Clock.finish();
		check("themes: starting rules before the first draw, then eased from", first == 0 && mid > 0.4 && mid < 0.6 && pop.style.opacity == 1,
			first + " " + mid + " " + pop.style.opacity);
		ui.root.remove(pop);
		ui.root.append(pop);
		ui.update();
		check("themes: again when it comes back", pop.style.opacity == 0, "" + pop.style.opacity);
		Clock.finish();
		// (one side of padding from one rule over the four from another; an auto margin from a rule)
		ui.theme = {rules: [
			{slot: "p", style: {padding: [8, 16]}},
			{slot: "p", when: ["data-dense"], style: {paddingTop: 2}},
			{slot: "row", style: {flexDirection: Row, width: 100}},
			{slot: "end", style: {width: 10, height: 10, marginLeft: Edges.AUTO}}
		]};
		var pn = new Node("p"), row = new Node("row"), end = new Node("end");
		pn.slot = "p";
		row.slot = "row";
		end.slot = "end";
		row.append(end);
		ui.root.append(pn);
		ui.root.append(row);
		pn.setAttr("data-dense", "");
		ui.update();
		ui.update();
		check("themes: padding-top over padding, an auto margin (ml-auto)", pn.style.padding.top == 2 && pn.style.padding.left == 16
			&& pn.style.padding.bottom == 8 && end.x == 90, pn.style.padding.top + " " + end.x);
		pn.setAttr("data-dense", null);
		ui.update();
		check("themes: the side back with the rule gone", pn.style.padding.top == 8 && pn.style.padding.left == 16, "" + pn.style.padding.top);
		ui.root.remove(pn);
		ui.root.remove(row);
		// (a radius from the sheet's lengths, calc(var(--radius) - 4px); another sheet, another radius)
		var rad = new Node("rad");
		rad.slot = "rad";
		ui.root.append(rad);
		ui.theme = {rules: [{slot: "rad", style: {borderRadius: Length.token("radius", -4), color: Color.rgb(0x112233), borderColor: Color.token("currentcolor")}}], lengths: ["radius" => 10.0]};
		ui.update();
		var first = rad.style.borderRadius;
		check("themes: currentColor beside a resolved length", rad.style.borderColor == Color.rgb(0x112233), "" + rad.style.borderColor);
		ui.theme = {rules: [{slot: "rad", style: {borderRadius: Length.token("radius", -4)}}], lengths: ["radius" => 2.0]};
		ui.update();
		check("themes: a radius from the sheet's lengths (clamped at 0)", first == 6 && rad.style.borderRadius == 0 && Length.tokenOffset(Length.token("x", -2.5)) == -2.5,
			first + " " + rad.style.borderRadius);
		ui.root.remove(rad);
		// (other nodes' states: a group's hover, a named peer's attribute, a descendant's, first and last, not)
		ui.theme = {
			rules: [
				{slot: "gi", style: {opacity: 0.5}},
				{slot: "gi", when: ["group:hover"], style: {opacity: 1}},
				{slot: "pi", when: ["peer/box:data-state=checked"], style: {opacity: 0.25}},
				{slot: "hb", when: ["has:data-state=open"], style: {opacity: 0.75}},
				{slot: "hb", when: ["has:>data-slot=pi"], style: {zIndex: 2}},
				{slot: "li", when: ["first"], style: {opacity: 0.1}},
				{slot: "li", when: ["last"], style: {opacity: 0.9}},
				{slot: "li", when: ["not:first", "not:last"], style: {opacity: 0.5}}
			]
		};
		var group = new Node("g"), inner = new Node("gi"), box = new Node("box"), peerOf = new Node("pi"), deep = new Node("deep");
		group.setAttr("group", "");
		inner.slot = "gi";
		box.setAttr("peer", "box");
		peerOf.slot = "pi";
		group.slot = "hb";
		var mid = new Node();
		mid.append(inner);
		mid.append(deep);
		group.append(mid);
		group.append(box);
		group.append(peerOf);
		ui.root.append(group);
		ui.update();
		var before = inner.style.opacity;
		@:privateAccess group.setState(true, false, false);
		ui.update();
		check("themes: group:hover from a hovered ancestor marked group", before == 0.5 && inner.style.opacity == 1, before + " " + inner.style.opacity);
		box.setAttr("data-state", "checked");
		deep.setAttr("data-state", "open");
		ui.update();
		check("themes: a named peer's attribute; has: a descendant's, a child's slot", peerOf.style.opacity == 0.25 && group.style.opacity == 0.75
			&& group.style.zIndex == 2, peerOf.style.opacity + " " + group.style.opacity + " " + group.style.zIndex);
		deep.setAttr("data-state", null);
		@:privateAccess group.setState(false, false, false);
		ui.update();
		check("themes: back as the others change", inner.style.opacity == 0.5 && group.style.opacity == 1, inner.style.opacity + " " + group.style.opacity);
		ui.root.remove(group);
		var list = new Node(), items = [for (i in 0...3) new Node("li" + i)];
		for (it in items) {
			it.slot = "li";
			list.append(it);
		}
		ui.root.append(list);
		ui.update();
		var placed = [for (it in items) it.style.opacity].join(" ");
		var extra = new Node("li3");
		extra.slot = "li";
		list.append(extra);
		list.remove(items[0]);
		ui.update();
		check("themes: first, last and not:, again as children come and go", placed == "0.1 0.5 0.9" && items[1].style.opacity == 0.1
			&& items[2].style.opacity == 0.5 && extra.style.opacity == 0.9, placed + " / " + items[1].style.opacity + " " + items[2].style.opacity + " " + extra.style.opacity);
		ui.root.remove(list);
		// (rules for a breakpoint: the window at least so wide; again across it)
		ui.theme = {rules: [{slot: "w", style: {opacity: 0.5}}, {slot: "w", when: ["md"], style: {opacity: 0.75}}]};
		var wide = new Node("w");
		wide.slot = "w";
		ui.root.append(wide);
		ui.update();
		var narrow = wide.style.opacity;
		ui.resize(800, 100);
		ui.update();
		check("themes: md rules from 768 pixels wide", narrow == 0.5 && wide.style.opacity == 0.75, narrow + " " + wide.style.opacity);
		ui.resize(100, 100);
		// (a rule for right to left: again when the direction changes)
		ui.theme = {rules: [{slot: "t", style: {opacity: 0.5}}, {slot: "t", when: ["rtl"], style: {opacity: 0.25}}]};
		var th = new Node("t");
		th.slot = "t";
		ui.root.append(th);
		ui.update();
		var ltr = th.style.opacity;
		ui.root.style.direction = Rtl;
		ui.update();
		check("themes: rtl rules, again when the direction changes", ltr == 0.5 && th.style.opacity == 0.25, ltr + " " + th.style.opacity);
		ui.root.style.direction = null;
		// (kept: the node's own padding over the rules', its default too, the sides as well; another node's the rules')
		ui.theme = {rules: [{slot: "k", style: {padding: 16, opacity: 0.5}}, {slot: "k", when: ["data-wide"], style: {paddingLeft: 24}}]};
		var kept = new Node("kept"), other = new Node("other");
		kept.slot = other.slot = "k";
		kept.setAttr("data-wide", "");
		Rules.keep(kept, ["padding"]);
		ui.root.append(kept);
		ui.root.append(other);
		ui.update();
		check("themes: Rules.keep holds a node's own padding (its default) over the rules", kept.style.paddingTop == 0 && kept.style.paddingLeft == 0
			&& kept.style.opacity == 0.5 && other.style.paddingTop == 16,
			kept.style.paddingTop + " " + kept.style.paddingLeft + " " + kept.style.opacity + " " + other.style.paddingTop);
		ui.root.remove(kept);
		ui.root.remove(other);
		ui.theme = null;
		// (a layer's text inherits the page's body's, as a popup in a page's body: again when it changes)
		var page = new Node("page"), layer = new Node("layer");
		page.slot = "body";
		page.style.fontSize = 20;
		ui.root.append(page);
		ui.overlay.append(layer);
		var first = layer.font().size;
		page.style.fontSize = 16;
		var again = layer.font().size;
		ui.root.remove(page);
		check("popups inherit the body's text (Ui.body)", first == 20 && again == 16 && layer.font().size != 16, first + " " + again + " " + layer.font().size);
		ui.overlay.remove(layer);
	}

	static function themes() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.alignItems = Start;
		var sheet:StyleSheet = {
			rules: [
				{slot: "button", style: {background: Color.parse("var(--primary)"), borderRadius: 6, padding: 8}},
				{slot: "button", when: ["hover"], style: {background: Color.parse("var(--primary)/50")}},
				{slot: "button", variant: "outline", style: {background: Color.TRANSPARENT, borderWidth: 1, borderColor: Color.parse("var(--border)")}},
				{slot: "button", size: "sm", style: {padding: 4}},
				{slot: "button", when: ["focus-visible"], style: {boxShadow: Shadow.parse("0 0 0 3px var(--ring)/50")}},
				{slot: "button", when: ["dark"], style: {borderRadius: 2}},
				{slot: "switch", style: {background: Color.parse("var(--input)")}},
				{slot: "switch", when: ["data-state=checked"], style: {background: Color.parse("var(--primary)")}},
				{slot: "input", when: ["placeholder"], style: {color: Color.parse("var(--muted-foreground)")}},
				{slot: "input", when: ["selection"], style: {background: Color.parse("var(--primary)/30")}}
			],
			light: ["primary" => Color.rgb(0x171717), "border" => Color.rgb(0xE5E5E5), "ring" => Color.rgb(0xA1A1A1), "input" => Color.rgb(0xE5E5E5),
				"muted-foreground" => Color.rgb(0x737373)],
			dark: ["primary" => Color.rgb(0xE5E5E5), "border" => Color.rgb(0x262626), "ring" => Color.rgb(0x737373), "input" => Color.rgb(0x333333),
				"muted-foreground" => Color.rgb(0xA1A1A1)]
		};
		var a = new Node("a"), b = new Node("b"), own = new Node("own"), sw = new Node("sw");
		for (n in [a, b, own, sw]) {
			n.style.set({width: 30, height: 20});
			ui.root.append(n);
		}
		a.slot = b.slot = own.slot = "button";
		b.variant = "outline";
		b.size = "sm";
		own.style.background = Color.rgb(0xFF0000);
		sw.slot = "switch";
		ui.update();
		check("themes: no sheet, no style", a.style.background == Color.TRANSPARENT && a.style.borderRadius == 0);
		ui.theme = sheet;
		ui.update();
		ui.update();
		check("themes: a slot's rules, tokens resolved", a.style.background == Color.rgb(0x171717) && a.style.borderRadius == 6 && a.style.padding.left == 8);
		ui.update();
		check("themes: a variant's and a size's rules after the slot's", b.style.background == Color.TRANSPARENT && b.style.borderWidth == 1
			&& b.style.borderColor == Color.rgb(0xE5E5E5) && b.style.padding.left == 4 && b.style.borderRadius == 6);
		ui.update();
		check("themes: the node's own style wins", own.style.background == Color.rgb(0xFF0000) && own.style.borderRadius == 6);
		// (hover: on and off again)
		ui.pointerMove(a.absX + 5, a.absY + 5);
		ui.update();
		check("themes: hover, an alpha on the token", a.style.background == Color.rgb(0x171717).fade(0.5), StringTools.hex(a.style.background));
		ui.pointerMove(190, 90);
		ui.update();
		check("themes: hover left", a.style.background == Color.rgb(0x171717));
		// (an attribute's state)
		ui.update();
		check("themes: an attribute's state, off", sw.style.background == Color.rgb(0xE5E5E5));
		sw.setAttr("data-state", "checked");
		ui.update();
		check("themes: data-state=checked", sw.style.background == Color.rgb(0x171717));
		sw.setAttr("data-state", "unchecked");
		ui.update();
		check("themes: data-state=unchecked", sw.style.background == Color.rgb(0xE5E5E5));
		// (focus-visible: a ring as a shadow, its token resolved)
		a.focusable = true;
		ui.keyDown(Key.TAB, 0);
		ui.update();
		check("themes: focus-visible", ui.focus == a && a.style.boxShadow != null && a.style.boxShadow.spread == 3 && a.style.boxShadow.color == Color.rgb(0xA1A1A1).fade(0.5));
		ui.pointerDown(190, 90, 1);
		ui.pointerUp(190, 90, 1);
		ui.update();
		check("themes: no ring after a press", a.style.boxShadow == null);
		// (dark: the dark colours, the rules for dark)
		ui.dark = true;
		ui.update();
		check("themes: dark", a.style.background == Color.rgb(0xE5E5E5) && a.style.borderRadius == 2 && sw.style.background == Color.rgb(0x333333));
		ui.dark = false;
		ui.update();
		check("themes: light again", a.style.background == Color.rgb(0x171717) && a.style.borderRadius == 6);
		// (a subtree's own sheet)
		var other:StyleSheet = {rules: [{slot: "button", style: {background: Color.rgb(0x00FF00)}}]};
		var box = new Node("box"), inner = new Node("inner");
		inner.slot = "button";
		box.append(inner);
		ui.root.append(box);
		box.theme = other;
		ui.update();
		check("themes: a subtree's sheet", inner.style.background == Color.rgb(0x00FF00) && inner.style.borderRadius == 0);
		box.theme = null;
		ui.update();
		check("themes: the window's again", inner.style.background == Color.rgb(0x171717) && inner.style.borderRadius == 6);
		// (a placeholder's colour)
		var f = new TextField("");
		f.slot = "input";
		ui.root.append(f);
		ui.update();
		check("themes: a placeholder's colour, a selection's", f.placeholderColor == Color.rgb(0x737373) && f.selectionColor == Color.rgb(0x171717).fade(0.3));
		// (no sheet: what the rules wrote taken back, the node's own kept)
		ui.theme = null;
		ui.update();
		check("themes: taken back", a.style.background == Color.TRANSPARENT && a.style.borderRadius == 0 && a.style.padding.left == 0 && b.style.borderWidth == 0
			&& own.style.background == Color.rgb(0xFF0000) && f.placeholderColor == Color.rgba(0, 0.4) && f.selectionColor == Color.rgba(0x3B82F6, 0.3));
		// (a change of the node's own after the rules: kept)
		ui.theme = sheet;
		a.style.borderRadius = 9;
		a.variant = "outline";
		ui.update();
		check("themes: a value set over the rules' kept", a.style.borderRadius == 9 && a.style.borderWidth == 1);
		// (tokens and oklch() in colours)
		var t = Color.parse("var(--ring)/50");
		ui.update();
		check("themes: token references", t.isToken && t.tokenName() == "ring" && t.tokenAlpha() == 0.5 && !Color.parse("rgba(255, 0, 0, 0)").isToken
			&& Color.parse("oklch(0.205 0 0)") == Color.rgb(0x171717) && Color.parse("oklch(0.577 0.245 27.325)") == Color.rgb(0xE7000B)
			&& Color.parse("oklch(1 0 0 / 10%)") == Color.rgba(0xFFFFFF, 0.1));
	}

	// --- paint ---

	// opacity: a group where more than one thing of the node is drawn (its
	// children, its content over its box), each quad's for a lone box; a
	// border's style and an outline's to the canvas's rect
	static function groups() {
		var ui = new Ui(new MonoText(), 200, 100);
		var parent = new Node(), lone = new Node(), child = new Node();
		parent.style.set({width: 80, height: 40, background: Color.WHITE, opacity: 0.5});
		child.style.set({width: 20, height: 20, background: Color.BLACK});
		parent.append(child);
		lone.style.set({width: 30, height: 30, borderWidth: 2, borderColor: Color.BLACK, opacity: 0.25});
		lone.style.borderStyle = Dashed;
		ui.root.append(parent);
		ui.root.append(lone);
		ui.update();
		var c = new Recording();
		ui.paint(c);
		var calls = c.calls.join("|");
		check("groups: a node with children a group", calls.indexOf("group 0.5 ") >= 0, calls);
		check("groups: a lone box its quads' opacity", calls.indexOf("opacity 0.25") >= 0 && calls.indexOf("group 0.25") < 0, calls);
		check("groups: a dashed border", calls.indexOf("ff000000 dashed") >= 0, calls);
		helder.ui.view.StyleAttrs.apply(lone.style, "borderStyle", "dotted");
		helder.ui.view.StyleAttrs.apply(lone.style, "outline", "1px solid black");
		helder.ui.view.StyleAttrs.apply(lone.style, "outlineStyle", "dashed");
		ui.update();
		var d = new Recording();
		ui.paint(d);
		calls = d.calls.join("|");
		check("groups: markup's border-style and outline-style", lone.style.borderStyle == Dotted && calls.indexOf("dotted") >= 0
			&& calls.indexOf("1 ff000000 dashed") >= 0, calls);
	}

	static function paint() {
		var ui = new Ui(new MonoText(), 200, 100);
		var a = new Node();
		a.style.set({width: 100, height: 50, borderRadius: 8, borderWidth: 2, background: Color.WHITE, borderColor: Color.BLACK,
			overflow: Hidden, boxShadow: Shadow.parse("1px 2px 6px 3 #00000080")});
		a.style.margin = 10;
		ui.root.append(a);
		var b = new Node();
		b.style.set({height: 10, background: Color.rgb(0xFF0000)});
		a.append(b);
		ui.update();
		var c = new Recording();
		ui.paint(c);
		var want = [
			"shadow 8 9 106 56 11 80000000 6",
			"rect 10 10 100 50 8 ffffffff 2 ff000000",
			"clip 12 12 96 46 6",
			"rect 12 12 96 10 0 ffff0000 0 0",
			"pop"
		];
		check("paint: calls", c.calls.join("|") == want.join("|"), c.calls.join("|"));
		// (a ring and its offset: over the shadow, as Tailwind composes them; each from its own property)
		a.style.set({ringWidth: 3, ringColor: Color.rgb(0xFF0000), ringOffsetWidth: 2});
		var r = new Recording();
		ui.paint(r);
		check("paint: a ring and its offset over the shadow", r.calls[0] == want[0] && r.calls[1] == "shadow 5 5 110 60 13 ffff0000 0"
			&& r.calls[2] == "shadow 8 8 104 54 10 ffffffff 0" && r.calls[3] == want[1], r.calls.slice(0, 4).join("|"));
		a.style.set({ringWidth: 0, ringOffsetWidth: 0});
		var sh = Shadow.parse("0 4");
		check("paint: Shadow.parse defaults", sh.x == 0 && sh.y == 4 && sh.blur == 0 && sh.spread == 0 && sh.color == 0x40000000);
		var threw = try {
			Shadow.parse("4");
			false;
		} catch (e:Dynamic) true;
		check("paint: Shadow.parse rejects one length", threw);
		var list = Shadow.parse("0 0 0 3px #3b82f6, inset 0 1px 3px rgba(0, 0, 0, 0.5)");
		check("paint: Shadow.parse, a list with inset and rgba()", list.spread == 3 && !list.inset && list.next != null && list.next.inset && list.next.y == 1
			&& list.next.blur == 3 && list.next.color == Color.rgba(0, 0.5) && list.next.next == null && list.painted()[0] == list.next);
		var ui2 = new Ui(new MonoText(), 200, 100);
		ui2.root.style.alignItems = Start;
		var sb = new Node("sb");
		sb.style.set({width: 40, height: 20, background: Color.rgb(0xFFFFFF), borderWidth: 2, borderColor: Color.rgb(0), boxShadow: list});
		ui2.root.append(sb);
		ui2.update();
		var rec2 = new Recording();
		ui2.paint(rec2);
		var kinds = [for (c in rec2.calls) c.split(" ")[0]];
		check("paint: outer shadows under the background, inset ones over it in the padding box", kinds.join(",") == "shadow,rect,inset"
			&& rec2.calls[2].indexOf("inset 2 2 36 16 0 ") == 0, rec2.calls.join("|"));
		// "none": no shadow; as a text shadow, stopping the parent's
		sb.style.boxShadow = Shadow.parse(" none ");
		var rec3 = new Recording();
		ui2.paint(rec3);
		check("paint: Shadow.parse(\"none\") draws none", sb.style.boxShadow == Shadow.NONE && rec3.calls.join("|").indexOf("shadow") < 0, rec3.calls.join("|"));
		// text shadows: inherited, under the text and its underline (the
		// last first), without a colour the text's; "none" stopping them
		var ui3 = new Ui(new MonoText(), 200, 100);
		ui3.root.style.alignItems = Start;
		var box = new Node("box");
		box.style.set({textShadow: Shadow.parse("1 2 4 #ff0000, -1 0"), color: Color.rgb(0x0000FF)});
		var t = new TextNode("ab");
		t.style.textDecoration = (TextDecoration.Underline : Int);
		box.append(t);
		var plain = new TextNode("cd");
		plain.style.textShadow = Shadow.NONE;
		box.append(plain);
		ui3.root.append(box);
		ui3.update();
		var rec4 = new Recording();
		ui3.paint(rec4);
		var calls = rec4.calls.join("|");
		var underline = [for (c in rec4.calls) if (c.indexOf("rect ") == 0) c];
		check("paint: text shadows, the last first, each under the text", rec4.calls.length == 7 && rec4.calls[1].indexOf("textShadow -1 0 ") == 0
			&& StringTools.endsWith(rec4.calls[1], " ff0000ff 0") && rec4.calls[3].indexOf("textShadow 1 2 ") == 0
			&& StringTools.endsWith(rec4.calls[3], " ffff0000 4") && rec4.calls[5].indexOf("text 0 0 ") == 0 && rec4.calls[6].indexOf("text 0 18 ") == 0, calls);
		check("paint: a text shadow's underline: offset, blurred as a box shadow", rec4.calls[0].indexOf("rect -1 ") == 0
			&& rec4.calls[2].indexOf("shadow 1 ") == 0 && StringTools.endsWith(rec4.calls[2], " ffff0000 4") && underline.length == 2, calls);
		check("paint: Shadow.NONE stops an inherited text shadow", t.textShadow() == box.style.textShadow && plain.textShadow() == null);
		// text-decoration-color: the lines' own colour, the glyphs keeping theirs
		t.style.set({textDecorationColor: Color.rgb(0x00FF00), textShadow: Shadow.NONE});
		var rec5 = new Recording();
		ui3.paint(rec5);
		var lines = [for (c in rec5.calls) if (c.indexOf("rect ") == 0) c];
		check("paint: text-decoration-color", lines.length == 1 && lines[0].indexOf(" ff00ff00 ") > 0 && rec5.calls.join("|").indexOf("text 0 0 14") >= 0,
			rec5.calls.join("|"));
		// its thickness (a percentage of the font size) and the underline's offset (inherited)
		var before = lines[0].split(" ");
		t.style.textDecorationThickness = "25%";
		box.style.textUnderlineOffset = 3;
		var rec7 = new Recording();
		ui3.paint(rec7);
		var after = [for (c in rec7.calls) if (c.indexOf("rect ") == 0) c][0].split(" ");
		check("paint: text-decoration-thickness and an inherited text-underline-offset", Std.parseFloat(after[4]) == t.font().size / 4
			&& Std.parseFloat(after[2]) == Std.parseFloat(before[2]) + 3, before.join(" ") + " | " + after.join(" "));
		t.style.textDecorationThickness = "auto";
		box.style.textUnderlineOffset = "auto";
		// an outline: around the border box, over the children, the focus ring over it
		var framed = new Node("framed"), inner = new Node("inner");
		framed.style.set({width: 20, height: 10, borderRadius: 4, outlineWidth: 2, outlineOffset: 1, color: Color.rgb(0x112233)});
		inner.style.set({height: 10, background: Color.rgb(0xFF0000)});
		framed.append(inner);
		framed.focusable = true;
		ui3.root.append(framed);
		ui3.update();
		ui3.keyDown(Key.TAB, 0);
		var rec6 = new Recording();
		ui3.paint(rec6);
		var at = rec6.calls.indexOf("rect " + framed.absX + " " + framed.absY + " 20 10 0 ffff0000 0 0");
		var o = "rect " + (framed.absX - 3) + " " + (framed.absY - 3) + " 26 16 7 0 2 ff112233";
		check("paint: an outline over the children, in the text colour, the ring over it", at >= 0 && rec6.calls[at + 1] == o
			&& rec6.calls[at + 2].indexOf("rect " + (framed.absX - 4)) == 0, rec6.calls.slice(at).join("|"));
		framed.parent.remove(framed);
		ui3.update();
		// a text field's text and placeholder: shadowed too
		var field = new TextField("");
		field.placeholder = "Name";
		field.style.set({width: 80, textShadow: Shadow.parse("0 1 2 #000000")});
		ui3.root.append(field);
		ui3.update();
		function fieldCalls() {
			var r = new Recording();
			ui3.paint(r);
			var at = r.calls.indexOf("clip " + field.absX + " " + field.absY + " 80 " + field.height + " 0");
			return [for (k in at + 1...r.calls.length) if (StringTools.startsWith(r.calls[k], "text")) r.calls[k].split(" ")[0]].join(",");
		}
		var placeholderCalls = fieldCalls();
		field.text = "Bo";
		check("paint: a text field's shadows under its placeholder and its text", placeholderCalls == "textShadow,text" && fieldCalls() == "textShadow,text",
			placeholderCalls + " | " + fieldCalls());
		// the focus ring: shown when Tab moves the focus, hidden by a press
		a.focusable = true;
		ui.keyDown(Key.TAB, 0);
		var c = new Recording();
		ui.paint(c);
		check("paint: the focus ring", ui.focus == a && c.calls[c.calls.length - 1] == "rect 6 6 108 58 12 0 2 ff3b82f6", c.calls[c.calls.length - 1]);
		// (outline-style none: no ring, a theme drawing its own)
		a.style.outlineStyle = None;
		var c2 = new Recording();
		ui.paint(c2);
		check("paint: outline-style none, no focus ring", c2.calls.length == c.calls.length - 1, c2.calls[c2.calls.length - 1]);
		a.style.outlineStyle = null;
		ui.pointerDown(50, 30, 1);
		ui.pointerUp(50, 30, 1);
		var c = new Recording();
		ui.paint(c);
		check("paint: no ring after a press", ui.focus == a && !ui.focusVisible && c.calls.length == want.length);
		// the cursor: the hovered node's, Auto taking the parent's
		check("cursor: Default by default", ui.cursor() == Default);
		a.style.cursor = Pointer;
		ui.pointerMove(50, 15);
		check("cursor: inherited from the parent", ui.hover == b && ui.cursor() == Pointer);
		b.style.cursor = Text;
		check("cursor: the node's own", ui.cursor() == Text);
		ui.pointerMove(190, 90);
		check("cursor: outside", ui.cursor() == Default);
		// over what is pressed: the arrow, or a browser's hand (pressCursor), Default while disabled
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.set({flexDirection: Row});
		var button = new Node("button"), off = new Node("off"), field = new TextField(""), plain = new TextNode("hi");
		button.append(new TextNode("OK"));
		off.semantics = ({role: helder.ui.access.Role.Button, disabled: true} : helder.ui.access.Semantics);
		for (n in [button, off, field, plain]) {
			n.style.set({width: 40, height: 20});
			ui.root.append(n);
		}
		ui.update();
		var over = (x:Float) -> {
			ui.pointerMove(x, 10);
			return ui.cursor();
		};
		check("cursor: the arrow over a button natively", over(5) == Default);
		ui.pressCursor = Pointer;
		check("cursor: pressCursor over a button's label", over(5) == Pointer);
		check("cursor: Default over a disabled button", over(45) == Default);
		check("cursor: a field's I-beam", over(85) == Text);
		check("cursor: Default over plain text", over(125) == Default);
		button.style.cursor = Crosshair;
		check("cursor: the button's own", over(5) == Crosshair);
	}

	// --- layout against Chromium ---

	static function layouts(here:String) {
		var cases:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(here + "/layout-cases.json"));
		var expected:Dynamic = haxe.Json.parse(sys.io.File.getContent(here + "/layout-expected.json"));
		for (c in cases) {
			var ui = new Ui(new MonoText(), c.width, c.height);
			build(ui.root, c.tree);
			ui.update();
			var want:Array<Array<Int>> = Reflect.field(expected, c.name);
			var got = [];
			// (a node not displayed, and what it holds: no box, as Chromium reads them)
			function walk(n:Node, hidden:Bool) {
				hidden = hidden || n.style.display == None;
				got.push(hidden ? [0, 0, 0, 0] : [Std.int(n.absX), Std.int(n.absY), Std.int(n.width), Std.int(n.height)]);
				for (ch in n.children)
					walk(ch, hidden);
			}
			walk(ui.root, false);
			var same = want.length == got.length;
			var detail = [];
			for (i in 0...Std.int(Math.min(want.length, got.length)))
				if (want[i].join(",") != got[i].join(",")) {
					same = false;
					detail.push('box $i: [${got[i].join(", ")}], Chromium [${want[i].join(", ")}]');
				}
			check('layout: ${c.name}', same, detail.join("; "));
		}
	}

	static function build(n:Node, d:Dynamic) {
		var style:Dynamic = d.style;
		if (style != null)
			for (k in Reflect.fields(style))
				setStyle(n.style, k, Reflect.field(style, k));
		var children:Array<Dynamic> = d.children;
		if (children != null)
			for (c in children) {
				var ch = new Node();
				n.append(ch);
				build(ch, c);
			}
	}

	static function dim(v:Dynamic):Dim {
		if (Std.isOfType(v, String)) {
			var s:String = v;
			return s == "auto" || StringTools.endsWith(s, "content") ? Dim.parse(s) : Percent(Std.parseFloat(s.substr(0, s.length - 1)));
		}
		return Px(v);
	}

	static function setStyle(s:Style, k:String, v:Dynamic) {
		switch k {
			case "width": s.width = dim(v);
			case "height": s.height = dim(v);
			case "minWidth": s.minWidth = dim(v);
			case "minHeight": s.minHeight = dim(v);
			case "maxWidth": s.maxWidth = dim(v);
			case "maxHeight": s.maxHeight = dim(v);
			case "basis": s.flexBasis = dim(v);
			case "left": s.left = dim(v);
			case "top": s.top = dim(v);
			case "right": s.right = dim(v);
			case "bottom": s.bottom = dim(v);
			case "grow": s.flexGrow = v;
			case "shrink": s.flexShrink = v;
			case "aspectRatio": s.aspectRatio = v;
			case "wrap": s.flexWrap = v;
			case "rowGap": s.rowGap = v;
			case "columnGap": s.columnGap = v;
			case "gap": s.gap = v;
			case "inset": s.inset = (v : Float);
			case "flex": s.flex = v;
			case "borderWidth": s.borderWidth = v;
			case "borders": s.borders = (v : Array<Float>);
			case "padding": s.padding = Std.isOfType(v, Array) ? (v : Array<Float>) : (v : Float);
			// ("auto": NaN)
			case "margin": s.margin = Std.isOfType(v, Array) ? [for (x in (v : Array<Dynamic>)) x == "auto" ? Math.NaN : (x : Float)] : v == "auto" ? Math.NaN : (v : Float);
			case "dir": s.direction = v == "Rtl" ? Rtl : Ltr;
			case "order": s.order = v;
			case "direction": s.flexDirection = switch (v : String) {
					case "Row": Row;
					case "RowReverse": RowReverse;
					case "ColumnReverse": ColumnReverse;
					case _: Column;
				}
			case "justify": s.justifyContent = switch (v : String) {
					case "End": End;
					case "Center": Center;
					case "SpaceBetween": SpaceBetween;
					case "SpaceAround": SpaceAround;
					case "SpaceEvenly": SpaceEvenly;
					case _: Start;
				}
			case "alignItems" | "alignSelf" | "justifyItems" | "justifySelf":
				var a:Align = switch (v : String) {
					case "Start": Start;
					case "End": End;
					case "Center": Center;
					case "Stretch": Stretch;
					case "Baseline": Baseline;
					case _: Auto;
				}
				switch k {
					case "alignItems": s.alignItems = a;
					case "alignSelf": s.alignSelf = a;
					case "justifyItems": s.justifyItems = a;
					case _: s.justifySelf = a;
				}
			case "gridTemplateColumns": s.gridTemplateColumns = Grid.tracks(v);
			case "gridTemplateRows": s.gridTemplateRows = Grid.tracks(v);
			case "gridAutoColumns": s.gridAutoColumns = Grid.tracks(v)[0];
			case "gridAutoRows": s.gridAutoRows = Grid.tracks(v)[0];
			case "gridAutoFlow": s.gridAutoFlow = switch v {
					case "Column": Grid.GridFlow.Column;
					case "RowDense": Grid.GridFlow.RowDense;
					case "ColumnDense": Grid.GridFlow.ColumnDense;
					case _: Grid.GridFlow.Row;
				}
			case "gridColumn": s.gridColumn = Grid.GridPlacement.parse(Std.string(v));
			case "gridRow": s.gridRow = Grid.GridPlacement.parse(Std.string(v));
			case "gridArea": s.gridArea = Std.string(v);
			case "gridTemplateAreas": s.gridTemplateAreas = Grid.GridAreas.parse(v);
			case "alignContent": s.alignContent = switch (v : String) {
					case "End": End;
					case "Center": Center;
					case "Stretch": Stretch;
					case "SpaceBetween": SpaceBetween;
					case "SpaceAround": SpaceAround;
					case "SpaceEvenly": SpaceEvenly;
					case _: Start;
				}
			case "position": s.position = v == "Absolute" ? Absolute : Relative;
			case "display": s.display = v == "None" ? None : v == "Grid" ? Grid : Flex;
			case "overflow": s.overflow = v == "Hidden" ? Hidden : v == "Scroll" ? Scroll : Visible;
			case _: throw "UiCheck: no style " + k;
		}
	}

	// --- text ---

	static function texts() {
		var ui = new Ui(new MonoText(), 200, 200);
		ui.root.style.fontSize = 16;
		ui.root.style.lineHeight = 1.5;
		ui.root.style.alignItems = Start;
		var t = new TextNode("hello world");
		ui.root.append(t);
		ui.update();
		check("text: one line", t.width == 88 && t.height == 24, '$t');
		t.text = "the quick brown fox jumps over the lazy dog";
		ui.update();
		// (25 characters a line at 8 pixels: three lines)
		check("text: wrapped to the parent", t.width == 200 && t.height == 48, '$t');
		var row = new Node();
		row.style.flexDirection = Row;
		row.style.width = 100;
		row.style.alignItems = Start;
		var a = new TextNode("aaa bbb");
		var b = new TextNode("cc");
		a.style.fontSize = 8;
		row.append(a);
		row.append(b);
		ui.root.append(row);
		ui.update();
		check("text: inherited and own font sizes", a.width == 28 && a.height == 12 && b.x == 28 && b.width == 16 && b.height == 24, '$a $b');
		var p = a.laidOut();
		check("text: paragraph", p != null && p.lineCount == 1 && p.caret(3).x == 12);
		check("text: font resolves", b.font().size == 16 && b.font().lineHeight == 1.5 && a.font().size == 8);
		// (a line height in pixels, inherited as pixels: 20 at 8 and at 16; em letter spacing, the pixels at its node)
		row.style.lineHeightPx = 20;
		row.style.letterSpacingEm = 0.25;
		ui.update();
		check("text: line height in pixels, letter spacing in em", a.height == 20 && b.height == 20 && a.font().lineHeight == 2.5
			&& b.font().lineHeight == 1.25 && a.font().letterSpacing == 4 && b.font().letterSpacing == 4, a.height + " " + b.height + " " + a.font().letterSpacing);
		row.style.lineHeight = 3;
		ui.update();
		check("text: pixels over a multiple on one node", b.height == 20, "" + b.height);
		row.style.lineHeightPx = null;
		row.style.letterSpacingEm = null;
		row.style.lineHeight = null;
		ui.update();
		// a long word in a narrow column: cut
		var narrow = new TextNode("abcdefghij");
		narrow.style.width = 40;
		ui.root.append(narrow);
		ui.update();
		check("text: a word cut to the width", narrow.height == 48, '$narrow');
	}

	// --- events ---

	static function events() {
		var ui = new Ui(new MonoText(), 300, 200);
		var log = [];
		var panel = new Node("panel");
		panel.style.flexDirection = Row;
		panel.style.padding = 10;
		panel.style.columnGap = 10;
		var a = new Node("a"), b = new Node("b"), inner = new Node("inner");
		for (n in [a, b]) {
			n.style.width = 100;
			n.style.height = 50;
			n.focusable = true;
			panel.append(n);
		}
		inner.style.width = 20;
		inner.style.height = 20;
		b.append(inner);
		ui.root.append(panel);
		for (n in [ui.root, panel, a, b, inner]) {
			var name = n.tag;
			n.onPointerDown = e -> log.push('down $name<-${e.target.tag}');
			n.onClick = e -> log.push('click $name');
			n.onPointerEnter = e -> log.push('enter $name');
			n.onPointerLeave = e -> log.push('leave $name');
			n.onFocus = e -> log.push('focus $name');
			n.onBlur = e -> log.push('blur $name');
			n.onKeyDown = e -> log.push('key $name ${e.key}');
		}
		ui.update();
		check("events: hit test", ui.root.hitTest(15, 15) == a && ui.root.hitTest(125, 15) == inner && ui.root.hitTest(150, 40) == b
			&& ui.root.hitTest(5, 5) == panel && ui.root.hitTest(250, 150) == ui.root);
		ui.pointerMove(130, 15);
		check("events: enter, outermost first", log.join("|") == "enter root|enter panel|enter b|enter inner", log.join("|"));
		log.resize(0);
		ui.pointerMove(150, 40);
		check("events: leave the child only", log.join("|") == "leave inner" && b.hovered && !inner.hovered, log.join("|"));
		log.resize(0);
		inner.onClick = e -> {
			log.push("click inner (stopped)");
			e.stop();
		};
		ui.pointerDown(125, 15, 1);
		// (inner is entered again: the pointer moved onto it)
		check("events: down bubbles, then focus", log.join("|") == "enter inner|down inner<-inner|down b<-inner|down panel<-inner|down root<-inner|focus b"
			&& ui.focus == b && b.focused && inner.pressed && b.pressed, log.join("|"));
		log.resize(0);
		ui.pointerUp(126, 16, 1);
		check("events: click stopped at the target", log.join("|") == "click inner (stopped)" && !inner.pressed, log.join("|"));
		log.resize(0);
		// released elsewhere: no click
		ui.pointerDown(20, 20, 1);
		ui.pointerUp(250, 150, 1);
		check("events: no click when released outside", log.indexOf("click a") < 0 && ui.focus == a, log.join("|"));
		log.resize(0);
		ui.keyDown(Key.TAB, 0);
		check("events: Tab moves the focus", log.join("|") == "key a 65289|key panel 65289|key root 65289|blur a|focus b" && ui.focus == b, log.join("|"));
		ui.keyDown(Key.TAB, 0);
		check("events: Tab wraps", ui.focus == a);
		ui.keyDown(Key.TAB, Mods.SHIFT);
		check("events: Shift+Tab goes back", ui.focus == b);
		log.resize(0);
		ui.pointerDown(250, 150, 1);
		check("events: a click outside focusables blurs", ui.focus == null && log.indexOf("blur b") >= 0, log.join("|"));
		ui.pointerUp(250, 150, 1);
		// removing the hovered node
		ui.pointerMove(125, 15);
		b.remove(inner);
		check("events: a removed node is no longer hovered", ui.hover == null || ui.hover != inner);

		// scrolling
		var ui = new Ui(new MonoText(), 100, 100);
		var list = new Node("list");
		list.style.height = 100;
		list.style.overflow = Scroll;
		for (i in 0...10) {
			var item = new Node("item" + i);
			item.style.height = 30;
			item.style.flexShrink = 0;
			list.append(item);
		}
		ui.root.append(list);
		ui.update();
		check("scroll: content height", list.contentHeight == 300, '${list.contentHeight}');
		ui.wheel(50, 50, 0, 50);
		check("scroll: by the wheel", list.scrollY == 50);
		check("scroll: hit test follows", ui.root.hitTest(50, 15).tag == "item2", ui.root.hitTest(50, 15).tag);
		ui.wheel(50, 50, 0, 1000);
		check("scroll: clamped", list.scrollY == 200);
		ui.wheel(50, 50, 0, -5000);
		check("scroll: back to the top", list.scrollY == 0);
		// (overflow-y hidden: still clipped, not scrolled by the wheel, no scrollbar; scrollTo still moves it)
		list.style.overflowY = Hidden;
		ui.wheel(50, 50, 0, 50);
		var r = new Recording();
		ui.paint(r);
		var thumbs = r.calls.filter(c -> StringTools.startsWith(c, "rect 92")).length;
		ui.scrollTo(list, 0, 30);
		check("scroll: overflow-y hidden: clipped, not scrolled by the wheel, scrolled by scrollTo", list.style.overflow == Scroll && thumbs == 0
			&& list.scrollY == 30, list.scrollY + " " + thumbs);
		list.style.overflowY = Scroll;
		ui.scrollTo(list, 0, 0);
		// the keys, when the focus takes none of them: arrows by 40, pages by seven eighths, the ends; eased on the clock
		var item1 = list.children[1];
		item1.focusable = true;
		ui.setFocus(item1, false);
		ui.keyDown(Key.DOWN, 0);
		// (its start the first tick's, as a window's next frame: then half its duration on)
		var start = Clock.now + 1;
		Clock.tick(start);
		Clock.tick(start + ui.scrollDuration / 2);
		var mid = list.scrollY;
		Clock.finish();
		check("scroll keys: an arrow, eased", list.scrollY == 40 && mid > 0 && mid < 40, mid + " " + list.scrollY);
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.DOWN, 0);
		Clock.finish();
		check("scroll keys: twice before it ends, twice as far", list.scrollY == 120, "" + list.scrollY);
		ui.keyDown(Key.PAGE_UP, 0);
		Clock.finish();
		check("scroll keys: a page up", list.scrollY == 120 - 87.5, "" + list.scrollY);
		ui.keyDown(Key.END, 0);
		Clock.finish();
		var end = list.scrollY;
		ui.keyDown(Key.SPACE, Mods.SHIFT);
		Clock.finish();
		var shiftSpace = list.scrollY;
		ui.keyDown(Key.HOME, 0);
		Clock.finish();
		check("scroll keys: the end, Shift+Space up a page, home", end == 200 && shiftSpace == 112.5 && list.scrollY == 0, end + " " + shiftSpace + " " + list.scrollY);
		item1.onKeyDown = e -> if (e.key == Key.DOWN) e.preventDefault();
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.DOWN, Mods.CONTROL);
		Clock.finish();
		check("scroll keys: not a key the focus took, nor with Control", list.scrollY == 0, "" + list.scrollY);
		item1.onKeyDown = null;
		ui.scrollDuration = 0;
		ui.keyDown(Key.PAGE_DOWN, 0);
		check("scroll keys: at once without easing", list.scrollY == 87.5 && !Clock.active, "" + list.scrollY);
		ui.scrollDuration = 0.15;
		ui.scrollTo(list, 0, 0);
		ui.setFocus(null, false);
		// the scrollbar: a track from y 2 of 96 px at x 92, its thumb 96 * 100 / 300 = 32 px
		var clicks = 0;
		for (c in list.children)
			c.onClick = e -> clicks++;
		ui.pointerDown(95, 10, 1);
		ui.pointerMove(95, 42);
		check("scroll: dragging the thumb", list.scrollY == 100, '${list.scrollY}');
		ui.pointerMove(95, 500);
		check("scroll: the drag clamped", list.scrollY == 200, '${list.scrollY}');
		ui.pointerMove(95, 42);
		ui.pointerUp(95, 42, 1);
		ui.pointerDown(95, 90, 1);
		ui.pointerUp(95, 90, 1);
		check("scroll: a press on the track pages", list.scrollY == 200, '${list.scrollY}');
		ui.pointerDown(95, 5, 1);
		ui.pointerUp(95, 5, 1);
		check("scroll: and back", list.scrollY == 100, '${list.scrollY}');
		check("scroll: the scrollbar takes the presses", clicks == 0 && ui.capture == null);
		var c = new Recording();
		ui.paint(c);
		check("scroll: the thumb painted", c.calls[c.calls.length - 1] == "rect 92 34 6 32 3 59000000 0 0", c.calls[c.calls.length - 1]);
	}

	// --- relayout ---

	static function dirty() {
		var ui = new Ui(new MonoText(), 200, 200);
		var a = new Node(), b = new Node();
		a.style.height = 50;
		b.style.height = 50;
		ui.root.append(a);
		ui.root.append(b);
		ui.update();
		check("dirty: first layout", b.y == 50);
		a.style.height = 80;
		check("dirty: marked", @:privateAccess ui.root.dirty);
		ui.update();
		check("dirty: relaid", b.y == 80 && !@:privateAccess ui.root.dirty);
		ui.resize(100, 300);
		ui.update();
		check("dirty: resized", a.width == 100);
		var c = new Node();
		c.style.height = 10;
		ui.root.insert(c, 0);
		ui.update();
		check("dirty: insert", a.y == 10 && b.y == 90);
		ui.root.insert(c, 3);
		ui.update();
		check("dirty: move to the end", a.y == 0 && c.y == 130);
	}
}

// a Canvas that records its calls (UiCheck's paint)
// spellcheck (EditableText.spellcheck): a text area's by default, a field's
// asked; the misspelled words found and waved under, checked again a moment
// after a change (a Clock step), a correction and Add to Dictionary through
// SpellAction, a right click's menu; no checker: nothing
function spelling() {
	var check = UiCheck.check;
	var list = new WordList();
	helder.text.Spell.given = list;
	check("spellcheck: a text area's by default, not a field's", new TextArea("").spellcheck && !new TextField("").spellcheck);
	var ui = new Ui(new MonoText(), 300, 100);
	ui.root.style.fontSize = 10;
	ui.root.style.alignItems = Start;
	var g = new TextField("the quikc brwon fox");
	g.style.width = 200;
	g.spellcheck = true;
	ui.root.append(g);
	ui.update();
	var rec = new Recording();
	ui.paint(rec);
	check("spellcheck: the misspelled words", g.misspelled.join(",") == "4,9,10,15", g.misspelled.join(","));
	check("spellcheck: waved under", rec.calls.filter(s -> StringTools.startsWith(s, "path") && StringTools.endsWith(s, "stroke 1")).length == 2, rec.calls.join("|"));
	// (typed: checked again a moment later, the words known not asked again)
	ui.setFocus(g);
	g.select(g.text.length, g.text.length);
	ui.textInput(" jmups");
	ui.update();
	ui.paint(new Recording());
	check("spellcheck: not at once after a change", g.misspelled.join(",") == "4,9,10,15");
	var asked = list.asked;
	Clock.finish();
	ui.update();
	ui.paint(new Recording());
	check("spellcheck: a moment later", g.misspelled.join(",") == "4,9,10,15,20,25" && list.asked == asked + 1, g.misspelled.join(",") + " " + (list.asked - asked));
	// a right click on one: its menu (drawn here), its corrections
	var before = ui.overlay.children.length;
	ui.pointerDown(g.absX + 6 * 5 + 1, g.absY + 5, 3);
	ui.pointerUp(g.absX + 6 * 5 + 1, g.absY + 5, 3);
	ui.update();
	var menu = helder.ui.menu.DrawnMenu.current;
	check("spellcheck: its menu's items: the corrections, Add to Dictionary", menu != null && [for (i in @:privateAccess menu.items) i.label].join(",") == "quick,quirk,,Add to Dictionary",
		menu == null ? "none" : [for (i in @:privateAccess menu.items) i.label].join(","));
	check("spellcheck: a right click on a misspelled word: a menu", ui.overlay.children.length == before + 1, '${ui.overlay.children.length}');
	var n = 0;
	while (ui.overlay.children.length > before && n++ < 5) {
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
	}
	ui.dispatchAction(Correct(4, 9, "quick"), g);
	check("spellcheck: a correction", g.text == "the quick brwon fox jmups", g.text);
	ui.dispatchAction(AddToDictionary("brwon"), g);
	check("spellcheck: added to the dictionary", list.words.indexOf("brwon") >= 0 && g.misspelled.join(",") == "20,25", g.misspelled.join(","));
	g.spellcheck = false;
	ui.update();
	rec = new Recording();
	ui.paint(rec);
	check("spellcheck off: nothing waved", g.misspelled.length == 0 && rec.calls.filter(s -> StringTools.startsWith(s, "path")).length == 0);
	helder.text.Spell.given = null;
	var t = new TextArea("teh");
	ui.root.append(t);
	ui.update();
	ui.paint(new Recording());
	check("spellcheck: no checker (helder's text engine), nothing", t.misspelled.length == 0);
}

// a spellchecker of the tests' (helder.text.Spell.given): its words, those added
class WordList implements helder.text.SpellChecker {
	public var language(default, null) = "en_US";
	public final words = ["the", "quick", "brown", "fox", "a", "an"];
	public var asked = 0;

	public function new() {}

	public function check(w:String):Bool {
		asked++;
		return words.indexOf(w.toLowerCase()) >= 0;
	}

	public function suggest(w:String):Array<String>
		return w == "quikc" ? ["quick", "quirk"] : [];

	public function add(w:String)
		words.push(w.toLowerCase());

	public function remove(w:String)
		words.remove(w.toLowerCase());
}

// what a canvas is given, in order: each call's name, numbers and objects
// (UiCheck.replayed)
class Calls implements Canvas {
	public final log:Array<Dynamic> = [];

	public function new() {}

	// (numbers compared as written, objects by identity)
	public function same(o:Calls):Bool {
		if (log.length != o.log.length) return false;
		for (i in 0...log.length) {
			var a = log[i], b = o.log[i];
			if (Std.isOfType(a, Float) || Std.isOfType(b, Float) ? Std.string(a) != Std.string(b) : a != b) return false;
		}
		return true;
	}

	function add(name:String, args:Array<Dynamic>) {
		log.push(name);
		for (a in args)
			log.push(a);
	}

	public function translate(dx:Float, dy:Float)
		add("translate", [dx, dy]);

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners)
		add("clip", [x, y, w, h, radius, corners]);

	public function popClip()
		add("popClip", []);

	public function pushOpacity(a:Float)
		add("opacity", [a]);

	public function pushGroup(a:Float, x:Float, y:Float, w:Float, h:Float)
		add("group", [a, x, y, w, h]);

	public function popOpacity()
		add("popOpacity", []);

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		add("transform", [a, b, c, d, e, f]);

	public function popTransform()
		add("popTransform", []);

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges, style:BorderStyle = Solid)
		add("rect", [x, y, w, h, radius, (fill : Int), borderWidth, (border : Int), corners, sides, (cast style : Int)]);

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>)
		add("shadow", [x, y, w, h, radius, (color : Int), blur, corners, offset]);

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners)
		add("inset", [x, y, w, h, radius, (color : Int), blur, dx, dy, spread, corners]);

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>)
		add("text", [p, x, y, width, (cast align : Int), (color : Int), colors]);

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>)
		add("textShadow", [p, x, y, width, (cast align : Int), (color : Int), blur, colors]);

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners)
		add("image", [img, x, y, w, h, u0, v0, u1, v1, radius, corners]);

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke)
		add("path", [p, fill, stroke]);
}

// a node that strokes a path (UiCheck.replayed): a stroke made each paint
class Stroked extends Node {
	final line:Path;

	public function new(line:Path) {
		super();
		this.line = line;
	}

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		canvas.translate(x, y);
		canvas.path(line, width > 30 ? null : Color.BLACK, {width: 1.5, paint: Color.rgb(0x336699)});
		canvas.translate(-x, -y);
	}
}

// each call given to two canvases (UiCheck.replayed)
class Tee implements Canvas {
	final a:Canvas;
	final b:Canvas;

	public function new(a, b) {
		this.a = a;
		this.b = b;
	}

	public function translate(dx:Float, dy:Float) {
		a.translate(dx, dy);
		b.translate(dx, dy);
	}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {
		a.pushClip(x, y, w, h, radius, corners);
		b.pushClip(x, y, w, h, radius, corners);
	}

	public function popClip() {
		a.popClip();
		b.popClip();
	}

	public function pushOpacity(v:Float) {
		a.pushOpacity(v);
		b.pushOpacity(v);
	}

	public function pushGroup(v:Float, x:Float, y:Float, w:Float, h:Float) {
		a.pushGroup(v, x, y, w, h);
		b.pushGroup(v, x, y, w, h);
	}

	public function popOpacity() {
		a.popOpacity();
		b.popOpacity();
	}

	public function pushTransform(m0:Float, m1:Float, m2:Float, m3:Float, m4:Float, m5:Float) {
		a.pushTransform(m0, m1, m2, m3, m4, m5);
		b.pushTransform(m0, m1, m2, m3, m4, m5);
	}

	public function popTransform() {
		a.popTransform();
		b.popTransform();
	}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges, style:BorderStyle = Solid) {
		a.rect(x, y, w, h, radius, fill, borderWidth, border, corners, sides, style);
		b.rect(x, y, w, h, radius, fill, borderWidth, border, corners, sides, style);
	}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {
		a.shadow(x, y, w, h, radius, color, blur, corners, offset);
		b.shadow(x, y, w, h, radius, color, blur, corners, offset);
	}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners) {
		a.insetShadow(x, y, w, h, radius, color, blur, dx, dy, spread, corners);
		b.insetShadow(x, y, w, h, radius, color, blur, dx, dy, spread, corners);
	}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {
		a.text(p, x, y, width, align, color, colors);
		b.text(p, x, y, width, align, color, colors);
	}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {
		a.textShadow(p, x, y, width, align, color, blur, colors);
		b.textShadow(p, x, y, width, align, color, blur, colors);
	}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {
		a.image(img, x, y, w, h, u0, v0, u1, v1, radius, corners);
		b.image(img, x, y, w, h, u0, v0, u1, v1, radius, corners);
	}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {
		a.path(p, fill, stroke);
		b.path(p, fill, stroke);
	}
}

class Recording implements Canvas {
	public final calls:Array<String> = [];

	public function new() {}

	static function hex(c:Color):String
		return c == 0 ? "0" : StringTools.hex(c, 8).toLowerCase();

	public function translate(dx:Float, dy:Float)
		calls.push('translate $dx $dy');

	static function cs(c:Null<Corners>):String
		return c == null ? "" : ' corners ${c.topLeft},${c.topRight},${c.bottomRight},${c.bottomLeft}';

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners)
		calls.push('clip $x $y $w $h $radius' + cs(corners));

	public function popClip()
		calls.push("pop");

	public function pushOpacity(a:Float)
		calls.push('opacity $a');

	public function pushGroup(a:Float, x:Float, y:Float, w:Float, h:Float)
		calls.push('group $a $x $y $w $h');

	public function popOpacity()
		calls.push("popOpacity");

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		calls.push('transform $a $b $c $d $e $f');

	public function popTransform()
		calls.push("popTransform");

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges, style:BorderStyle = Solid)
		calls.push('rect $x $y $w $h $radius ${hex(fill)} $borderWidth ${hex(border)}' + cs(corners)
			+ (sides == null ? "" : ' sides ${sides.top},${sides.right},${sides.bottom},${sides.left}')
			+ (style == Dashed ? " dashed" : style == Dotted ? " dotted" : ""));

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>)
		calls.push('shadow $x $y $w $h $radius ${hex(color)} $blur' + cs(corners));

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners)
		calls.push('inset $x $y $w $h $radius ${hex(color)} $blur $dx $dy $spread' + cs(corners));

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>)
		calls.push('text $x $y $width' + (colors == null ? "" : " colors " + [for (c in colors) hex(c)].join(",")));

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>)
		calls.push('textShadow $x $y $width ${hex(color)} $blur' + (colors == null ? "" : " colors " + [for (c in colors) hex(c)].join(",")));

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners)
		calls.push('image ${img.width}x${img.height} $x $y $w $h $u0 $v0 $u1 $v1 $radius' + cs(corners));

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke)
		calls.push('path ${p.commands.length}' + (fill == null ? "" : " fill") + (stroke == null ? "" : ' stroke ${stroke.width}'));
}

// a clipboard whose reads are answered by the test, later (UiCheck's fields)
class LaterClipboard implements ClipboardHost {
	public final waiting:Array<Null<String>->Void> = [];

	public function new() {}

	public function write(text:String) {}

	public function read(callback:Null<String>->Void)
		waiting.push(callback);
}

// a platform's views for UiCheck.natives: editors that record what they are told
class FakeViews implements PlatformViews {
	public final made:Array<FakeEditor> = [];

	public function new() {}

	public function editor(multiline:Bool):Null<PlatformEditor> {
		var e = new FakeEditor(multiline);
		made.push(e);
		return e;
	}

	public function poll() {}

	public final menus:Array<{items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void}> = [];

	public function menu(items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool {
		menus.push({items: items, x: x, y: y, chosen: chosen});
		return true;
	}

	public var bar:Null<{menus:Array<PlatformMenuItem>, chosen:Int->Void}> = null;

	public function menuBar(menus:Array<PlatformMenuItem>, chosen:Int->Void):Bool {
		bar = {menus: menus, chosen: chosen};
		return true;
	}
}

class FakeEditor implements PlatformEditor {
	public function slot():Null<LayerSlot>
		return null;

	public final multiline:Bool;
	public var listener:Null<PlatformEditorListener> = null;
	public var text = "";
	public var placeholder = "";
	public var x = 0.0;
	public var y = 0.0;
	public var w = 0.0;
	public var h = 0.0;
	public var shown = false;
	public var focused = false;
	public var disposed = false;

	public function new(multiline:Bool)
		this.multiline = multiline;

	public function listen(l:PlatformEditorListener)
		listener = l;

	public var start = 0;
	public var end = 0;
	public var kind:Null<helder.os.TextKind> = null;

	public function setText(text:String, start:Int, end:Int) {
		this.text = text;
		select(start, end);
	}

	public function select(start:Int, end:Int) {
		this.start = start;
		this.end = end;
	}

	public function setKind(kind:helder.os.TextKind)
		this.kind = kind;

	public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool) {
		this.x = x;
		this.y = y;
		w = width;
		h = height;
		this.shown = shown;
	}

	public function setStyle(font:Font, color:Color, background:Color, placeholder:String, placeholderColor:Color, align:TextAlign, secret:Bool)
		this.placeholder = placeholder;

	public function focus(on:Bool)
		focused = on;

	public function dispose()
		disposed = true;
}

// (a system with no font at all)
class NoFonts extends helder.text.SystemFonts {
	override public function match(family:String, weight = 400, italic = false):Null<helder.text.FontFile>
		return null;
}
