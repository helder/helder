import helder.ui.*;
import helder.ui.DimValue;
import haxe.DynamicAccess;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.ui's layout against Taffy's fixtures (Chrome's boxes), on Eval
// (bun run test layout-conformance):
//
//   <tool> -cp src -cp tests/ui -cp tests/layout-conformance --run LayoutConformanceCheck
//
// Every fixture of manifest.json is decoded and validated (its tree, each
// variant's boxes, one a node); the manifest's variants are laid out and
// compared, each box within TOLERANCE pixels. A required case that fails, or
// a pending one that passes, fails the run. BLESS=1 writes the manifest's
// pending cases from the results instead (a reason kept while it still fails).
class LayoutConformanceCheck {
	static inline var TOLERANCE = 0.5;
	static final VARIANTS = ["border-box-ltr", "border-box-rtl", "content-box-ltr", "content-box-rtl"];

	static function main() {
		var here = "tests/layout-conformance";
		var bless = Sys.getEnv("BLESS") == "1";
		var only = Sys.args().length > 0 ? Sys.args()[0] : null;
		var manifest:Dynamic = haxe.Json.parse(File.getContent('$here/manifest.json'));
		need(manifest.schema == 1, "manifest: schema 1");
		need(Std.isOfType(manifest.taffy_revision, String), "manifest: taffy_revision");
		var run:Array<String> = manifest.variants;
		for (v in run)
			need(VARIANTS.contains(v), 'manifest: variant $v');
		var cases:Array<Dynamic> = manifest.cases;
		var seen = new Map<String, Bool>();
		var stats = new Map<String, {pass:Int, pending:Int, total:Int, fixed:Int}>();
		var categories = [];
		var failures = [], fixed = [];
		var blessed = [];
		for (c in cases) {
			var id:String = c.id;
			need(!seen.exists(id), 'manifest: $id twice');
			seen.set(id, true);
			var fixture:Dynamic = haxe.Json.parse(File.getContent('$here/fixtures/$id.json'));
			validate(id, fixture, manifest.taffy_revision);
			var pending:DynamicAccess<String> = c.pending ?? {};
			for (v in pending.keys())
				need(run.contains(v), '$id: pending $v is not a variant run');
			var category = id.split("/")[0];
			if (!stats.exists(category)) {
				stats.set(category, {pass: 0, pending: 0, total: 0, fixed: 0});
				categories.push(category);
			}
			var st = stats[category];
			var next:DynamicAccess<String> = {};
			for (v in run) {
				if (only != null && id.indexOf(only) < 0) continue;
				var wasPending = pending.exists(v);
				st.total++;
				// (skipped: decoded and validated, not laid out)
				if (c.skip != null) {
					need(wasPending, '$id: skipped but not pending');
					st.pending++;
					next[v] = pending[v];
					continue;
				}
				var r = layout(fixture, v);
				if (r.ok) {
					if (wasPending) {
						fixed.push('$id [$v]: passes now (pending: ${pending[v]})');
						st.fixed++;
					}
					st.pass++;
				} else {
					st.pending++;
					next[v] = wasPending && pending[v] != "new" ? pending[v] : r.reason;
					if (!wasPending) failures.push('$id [$v]: ${r.reason}');
				}
			}
			var out:Dynamic = {id: id};
			if (next.keys().length > 0) out.pending = next;
			if (c.skip != null) out.skip = c.skip;
			blessed.push(out);
		}
		// (every fixture listed)
		for (dir in FileSystem.readDirectory('$here/fixtures'))
			for (f in FileSystem.readDirectory('$here/fixtures/$dir'))
				need(seen.exists('$dir/${f.substr(0, f.length - 5)}'), 'fixtures/$dir/$f: not in the manifest');
		var pass = 0, total = 0;
		for (k in categories) {
			var s = stats[k];
			pass += s.pass;
			total += s.total;
			Sys.println('$k: ${s.pass} of ${s.total} pass, ${s.total - s.pass} pending');
		}
		Sys.println('LayoutConformanceCheck: ${cases.length} fixtures, $pass of $total cases pass (${run.join(", ")})');
		if (bless && only == null) {
			var head = File.getContent('$here/manifest.json');
			head = head.substr(0, head.indexOf('"cases": [') + 10);
			File.saveContent('$here/manifest.json', head + "\n" + [for (c in blessed) "\t\t" + haxe.Json.stringify(c)].join(",\n") + "\n\t]\n}\n");
			Sys.println("LayoutConformanceCheck: manifest.json written");
			return;
		}
		for (f in failures)
			Sys.println("FAIL " + f);
		for (f in fixed)
			Sys.println("FIXED " + f + " (BLESS=1 to require it)");
		#if !helder.layout
		// (on the CSS engine's layout, NodeBoxes: Layout's required cases it fails so far, fewer as the port goes on)
		Sys.println('LayoutConformanceCheck: ${failures.length} required failing on the engine, at most 32');
		if (failures.length > 32) Sys.exit(1);
		#else
		if (failures.length + fixed.length > 0) {
			Sys.println('LayoutConformanceCheck: ${failures.length} required failing, ${fixed.length} pending passing');
			Sys.exit(1);
		}
		#end
	}

	static function need(ok:Bool, what:String)
		if (!ok) throw "LayoutConformanceCheck: invalid " + what;

	// the fixture's shape (schema/fixture.schema.json), each variant one box a node
	static function validate(id:String, f:Dynamic, revision:String) {
		need(f.schema == 1 && f.id == id, '$id: schema, id');
		var u:Dynamic = f.upstream;
		need(u != null && u.repository == "https://github.com/DioxusLabs/taffy" && u.revision == revision && u.license == "MIT"
			&& Std.isOfType(u.path, String), '$id: upstream');
		need(f.viewport != null && f.rounding != null, '$id: viewport, rounding');
		var n = count(f.tree);
		var variants:DynamicAccess<Array<Array<Float>>> = f.variants;
		for (v in VARIANTS) {
			var b = variants[v];
			need(b != null && b.length == n, '$id: $v boxes');
			for (box in b)
				need(box.length == 4 && [for (x in box) if (Math.isNaN(x)) x].length == 0, '$id: $v box');
		}
	}

	static function count(t:Dynamic):Int {
		need(t.style != null, "tree: style");
		var n = 1;
		var ch:Array<Dynamic> = t.children ?? [];
		for (c in ch)
			n += count(c);
		return n;
	}

	// --- layout ---

	static function layout(f:Dynamic, variant:String):{ok:Bool, reason:String} {
		var notes = [];
		var ui = new Ui(new MonoText(), 100000, 100000);
		ui.root.style.fontSize = 10;
		ui.root.style.lineHeight = 1;
		// (the viewport: a flex row of the test's root at its start, max-content unless given)
		var viewport = new Node();
		var vs = viewport.style;
		vs.position = Absolute;
		vs.left = 0;
		vs.top = 0;
		vs.flexDirection = Row;
		vs.alignItems = Start;
		vs.width = Dim.parse(f.viewport.width);
		vs.height = Dim.parse(f.viewport.height);
		ui.root.append(viewport);
		var rtl = variant.endsWith("rtl");
		vs.direction = rtl ? Rtl : Ltr;
		var nodes = [];
		var root = build(f.tree, rtl, notes, nodes);
		// (the root: laid out in the available space, not by its position, as Taffy's)
		if (f.viewport.width == "max-content") root.style.position = Relative;
		viewport.append(root);
		ui.update();
		var want:Array<Array<Float>> = Reflect.field(f.variants, variant);
		var bad = [];
		for (i => n in nodes) {
			var hidden = false;
			var p = n;
			while (p != viewport) {
				if (p.style.display == None) hidden = true;
				p = p.parent;
			}
			var got = hidden ? [0.0, 0, 0, 0] : [n.absX - n.parent.absX, n.absY - n.parent.absY, n.width, n.height];
			var w = want[i];
			for (k in 0...4)
				if (Math.abs(got[k] - w[k]) > TOLERANCE) {
					bad.push('node $i [${got.join(" ")}], Chrome [${w.join(" ")}]');
					break;
				}
		}
		if (bad.length == 0) return {ok: true, reason: ""};
		var reason = notes.length > 0 ? "unmapped: " + notes.join("; ") : "differs: " + bad[0] + (bad.length > 1 ? ' (+${bad.length - 1})' : "");
		return {ok: false, reason: reason};
	}

	static function build(t:Dynamic, rtl:Bool, notes:Array<String>, nodes:Array<Node>):Node {
		var n:Node = t.text != null ? new AhemNode(t.text) : new Node();
		nodes.push(n);
		var s = n.style;
		s.direction = rtl ? Rtl : Ltr;
		// (CSS's initial values where helder.ui's differ)
		s.flexDirection = Row;
		s.alignItems = Stretch;
		var style:DynamicAccess<String> = t.style;
		var rowStart = "auto", rowEnd = "auto", colStart = "auto", colEnd = "auto";
		function note(what:String)
			if (!notes.contains(what)) notes.push(what);
		function px(k:String, v:String):Float {
			if (v.endsWith("%")) {
				note('$k: a percentage');
				return 0;
			}
			return Std.parseFloat(v);
		}
		function margin(k:String, v:String):Float
			return v == "auto" ? Math.NaN : px(k, v);
		function dim(k:String, v:String):Dim {
			if (v == "stretch" || v == "content" || v.startsWith("fit-content(")) {
				note('$k: $v');
				return DimValue.Auto;
			}
			return Dim.parse(v);
		}
		function unsafe(k:String, v:String):String {
			if (v.startsWith("safe ")) {
				note('$k: safe');
				return v.substr(5);
			}
			if (v.startsWith("self-")) note('$k: $v');
			return v.startsWith("unsafe ") ? v.substr(7) : v;
		}
		function align(k:String, v:String):Align {
			var w = unsafe(k, v);
			return switch w {
				case "start" | "flex-start" | "self-start": Start;
				case "end" | "flex-end" | "self-end": End;
				case "center": Center;
				case "stretch": Stretch;
				case "baseline": Baseline;
				case "auto": Auto;
				case _: note('$k: $v'); Auto;
			}
		}
		function tracks(k:String, v:String):Array<Grid.Track> {
			if (v.indexOf("[") >= 0) note('$k: named lines');
			if (v.indexOf("fit-content(") >= 0) note('$k: fit-content()');
			if (v.indexOf("auto-fit") >= 0 || v.indexOf("auto-fill") >= 0) note('$k: repeat(auto-fit/auto-fill)');
			return try Grid.tracks(v) catch (e:Dynamic) {
				note('$k: not parsed');
				[];
			}
		}
		for (k => v in style)
			switch k {
				case "display": s.display = switch v {
						case "grid": Grid;
						case "block": Block;
						case "none": None;
						case _: Flex;
					}
				case "position":
					s.position = v == "absolute" ? Absolute : Relative;
					// (static: relative but for its offsets and its absolute children's containing block)
					if (v == "static") {
						var ch:Array<Dynamic> = t.children ?? [];
						if ([for (k in ["top", "right", "bottom", "left"]) if (style.exists(k)) k].length > 0
							|| [for (c in ch) if ((c.style : DynamicAccess<String>).get("position") == "absolute") c].length > 0)
							note("position: static");
					}
				case "flex-direction": s.flexDirection = switch v {
						case "column": Column;
						case "row-reverse": RowReverse;
						case "column-reverse": ColumnReverse;
						case _: Row;
					}
				case "flex-wrap":
					if (v != "wrap" && v != "nowrap") note('flex-wrap: $v');
					s.flexWrap = v != "nowrap";
				case "flex-grow": s.flexGrow = Std.parseFloat(v);
				case "flex-shrink": s.flexShrink = Std.parseFloat(v);
				case "flex-basis": s.flexBasis = dim(k, v);
				case "width": s.width = dim(k, v);
				case "height": s.height = dim(k, v);
				case "min-width": s.minWidth = dim(k, v);
				case "min-height": s.minHeight = dim(k, v);
				case "max-width": s.maxWidth = dim(k, v);
				case "max-height": s.maxHeight = dim(k, v);
				case "top": s.top = dim(k, v);
				case "left": s.left = dim(k, v);
				case "right": s.right = dim(k, v);
				case "bottom": s.bottom = dim(k, v);
				case "aspect-ratio": s.aspectRatio = Std.parseFloat(v);
				case "margin-top": s.marginTop = margin(k, v);
				case "margin-right": s.marginRight = margin(k, v);
				case "margin-bottom": s.marginBottom = margin(k, v);
				case "margin-left": s.marginLeft = margin(k, v);
				case "padding-top": s.paddingTop = px(k, v);
				case "padding-right": s.paddingRight = px(k, v);
				case "padding-bottom": s.paddingBottom = px(k, v);
				case "padding-left": s.paddingLeft = px(k, v);
				case "border-top" | "border-right" | "border-bottom" | "border-left": // (below)
				case "row-gap": s.rowGap = px(k, v);
				case "column-gap": s.columnGap = px(k, v);
				case "align-items": s.alignItems = align(k, v);
				case "align-self": s.alignSelf = align(k, v);
				case "justify-items": s.justifyItems = align(k, v);
				case "justify-self": s.justifySelf = align(k, v);
				case "align-content": s.alignContent = switch unsafe(k, v) {
						case "start" | "flex-start": Start;
						case "end" | "flex-end": End;
						case "center": Center;
						case "stretch": Stretch;
						case "space-between": SpaceBetween;
						case "space-around": SpaceAround;
						case "space-evenly": SpaceEvenly;
						case _: note('$k: $v'); Normal;
					}
				case "justify-content": s.justifyContent = switch unsafe(k, v) {
						case "start" | "flex-start": Start;
						case "end" | "flex-end": End;
						case "center": Center;
						case "space-between": SpaceBetween;
						case "space-around": SpaceAround;
						case "space-evenly": SpaceEvenly;
						case "stretch": Normal;
						case _: note('$k: $v'); Normal;
					}
				case "overflow-x": s.overflowX = overflow(v);
				case "overflow-y": s.overflowY = overflow(v);
				case "scrollbar-width": note("scrollbar-width: a gutter");
				case "direction": s.direction = v == "rtl" ? Rtl : Ltr;
				case "box-sizing": if (v != "border-box") note('box-sizing: $v');
				// (Taffy's, with flex-wrap: balance)
				case "flex-line-count":
				case "grid-template-columns": s.gridTemplateColumns = tracks(k, v);
				case "grid-template-rows": s.gridTemplateRows = tracks(k, v);
				case "grid-auto-columns" | "grid-auto-rows":
					var t = tracks(k, v);
					if (t.length > 1) note('$k: several tracks');
					if (t.length > 0) if (k == "grid-auto-columns") s.gridAutoColumns = t[0] else s.gridAutoRows = t[0];
				case "grid-auto-flow": s.gridAutoFlow = switch v {
						case "column": Grid.GridFlow.Column;
						case "row dense": Grid.GridFlow.RowDense;
						case "column dense": Grid.GridFlow.ColumnDense;
						case _: Grid.GridFlow.Row;
					}
				case "grid-row-start": rowStart = v;
				case "grid-row-end": rowEnd = v;
				case "grid-column-start": colStart = v;
				case "grid-column-end": colEnd = v;
				case _: note('$k: $v');
			}
		// (a block: helder.ui's column, not a flex row)
		if (s.display == Block && !style.exists("flex-direction")) s.flexDirection = Column;
		// (start and end, not flex-start and flex-end: the same but in a reverse flex direction)
		if (s.display != Grid && (s.flexDirection == RowReverse || s.flexDirection == ColumnReverse))
			for (k in ["justify-content", "align-content"])
				if (style.exists(k) && ~/(^| )(start|end)$/.match(style[k])) note('$k: ${style[k]} in a reverse direction');
		if (style.exists("border-top") || style.exists("border-right") || style.exists("border-bottom") || style.exists("border-left")) {
			inline function b(k:String)
				return style.exists(k) ? px(k, style[k]) : 0.0;
			s.borders = [b("border-top"), b("border-right"), b("border-bottom"), b("border-left")];
		}
		inline function place(a:String, b:String)
			return try Grid.GridPlacement.parse('$a / $b') catch (e:Dynamic) {
				note('grid line: $a / $b');
				Grid.GridPlacement.AUTO;
			}
		if (rowStart != "auto" || rowEnd != "auto") s.gridRow = place(rowStart, rowEnd);
		if (colStart != "auto" || colEnd != "auto") s.gridColumn = place(colStart, colEnd);
		var children:Array<Dynamic> = t.children ?? [];
		for (c in children)
			n.append(build(c, rtl, notes, nodes));
		return n;
	}

	static function overflow(v:String):Overflow
		return v == "hidden" ? Hidden : v == "scroll" || v == "auto" ? Scroll : Visible;
}

// Taffy's text measure (tests/common, AhemTextMeasureData): the Ahem font at
// 10px, line-height 1, each character 10 pixels square, lines broken only at
// zero-width spaces (U+200B); its first baseline 8 pixels down
class AhemNode extends Node {
	static inline var H = 10.0;

	final words:Array<Int>;

	public function new(text:String) {
		super("text");
		words = [for (w in text.split("​")) w.length];
	}

	override public function hasContent():Bool
		return true;

	override public function measureContent(text:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var min = 0, max = 0;
		for (w in words) {
			if (w > min) min = w;
			max += w;
		}
		var size = !Math.isNaN(knownWidth) ? knownWidth : Math.isNaN(availWidth) ? max * H : Math.min(availWidth, max * H);
		size = Math.max(size, min * H);
		if (!Math.isNaN(knownHeight)) return new Size(size, knownHeight);
		var perLine = Math.floor(size / H), lines = 1, current = 0;
		for (w in words)
			if (current + w > perLine) {
				if (current > 0) lines++;
				current = w;
			} else
				current += w;
		return new Size(size, lines * H);
	}

	override public function firstBaseline():Float
		return style.paddingTop + style.borderEdges.top + 8;
}
