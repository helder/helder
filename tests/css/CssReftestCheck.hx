import haxe.DynamicAccess;
import haxe.Json;
import haxe.io.Bytes;
import helder.canvas.Canvas;
import helder.ui.box.DocumentView;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// WPT's CSS reftests drawn by helder.ui.box (natively, on the CPU canvas):
// each in-scope test of fixtures/reftests.json and its references at
// 800 by 600, their pixels compared as WPT's runner compares them (`==`
// all alike, `!=` not, within the test's <meta name=fuzzy>); a crash
// test passes when it draws. reftest-manifest.json is the gate: every
// test is required to pass unless it is pending (its stage, and why) or
// skipped; a pending test that passes fails the run too, until BLESS=1
// writes the manifest from the results. Per chapter counts at the end.
//
//   CssReftestCheck [filter...]   (a directory or test name's part: those alone)
class CssReftestCheck {
	static final here = "tests/css";
	static inline var W = 800;
	static inline var H = 600;

	static function main() {
		var filters = Sys.args();
		var bless = Sys.getEnv("BLESS") == "1";
		// (each test's name before it is drawn: which one hangs or crashes)
		var verbose = Sys.getEnv("VERBOSE") == "1";
		var fixtures:Dynamic = Json.parse(File.getContent('$here/fixtures/reftests.json'));
		var manifestPath = '$here/reftest-manifest.json';
		var manifest:DynamicAccess<Dynamic> = FileSystem.exists(manifestPath) ? Json.parse(File.getContent(manifestPath)).cases : {};
		if (!FileSystem.exists('${WptPage.wpt}/css/CSS2')) {
			Sys.println('CssReftestCheck: no ${WptPage.wpt} (node tests/css/import-wpt.mjs --checkout)');
			Sys.exit(1);
		}
		var dirs:DynamicAccess<Dynamic> = fixtures.directories;
		var next:DynamicAccess<Dynamic> = {};
		var stats = new Map<String, {pass:Int, pending:Int, skip:Int, total:Int}>();
		var failures = [], fixed = [];
		var t0 = haxe.Timer.stamp();
		var ran = 0;
		var names = [for (k in dirs.keys()) k];
		names.sort(Reflect.compare);
		for (dir in names) {
			var tests:Array<Dynamic> = dirs[dir].tests != null ? dirs[dir].tests : [];
			for (t in tests) {
				var name:String = t.name;
				var id = '$dir/$name';
				var type:Null<String> = t.type;
				if (type == "noref") continue;
				var entry:Dynamic = manifest[id];
				var wanted = filters.length == 0 || Lambda.exists(filters, f -> id.indexOf(f) >= 0);
				if (!wanted) {
					if (entry != null) next[id] = entry;
					continue;
				}
				var st = stats.get(dir);
				if (st == null) stats.set(dir, st = {pass: 0, pending: 0, skip: 0, total: 0});
				st.total++;
				var skip = entry == null ? skipped(dir, t) : entry.skip;
				if (skip != null) {
					st.skip++;
					next[id] = {skip: skip};
					continue;
				}
				ran++;
				if (verbose) Sys.println(id);
				var r = run(dir, t);
				var pending:Null<String> = entry == null ? "new" : entry.pending;
				if (r.pass) {
					st.pass++;
					if (pending != null && entry != null) fixed.push('$id (pending: $pending)');
					next[id] = {};
				} else {
					st.pending++;
					if (pending == null) failures.push('$id: ${r.why}');
					next[id] = {pending: pending == null || pending == "new" || bless ? reason(dir, t, r.why, pending) : pending};
				}
			}
		}
		var total = {pass: 0, pending: 0, skip: 0, total: 0};
		for (dir in names) {
			var s = stats.get(dir);
			if (s == null) continue;
			Sys.println('${dir.rpad(" ", 44)} ${Std.string(s.pass).lpad(" ", 4)} of ${Std.string(s.total - s.skip).lpad(" ", 4)} pass, ${s.pending} pending, ${s.skip} skipped');
			total.pass += s.pass;
			total.pending += s.pending;
			total.skip += s.skip;
			total.total += s.total;
		}
		Sys.println('all: ${total.pass} of ${total.total - total.skip} pass, ${total.pending} pending, ${total.skip} skipped ($ran drawn in ${Math.round(haxe.Timer.stamp() - t0)} s)');
		if (bless) {
			if (filters.length > 0) for (k => v in manifest) if (!next.exists(k)) next[k] = v;
			var keys = [for (k in next.keys()) k];
			keys.sort(Reflect.compare);
			var lines = [for (k in keys) '\t\t${Json.stringify(k)}: ${Json.stringify(next[k])}'];
			File.saveContent(manifestPath, '{\n\t"schema": 1,\n\t"cases": {\n${lines.join(",\n")}\n\t}\n}\n');
			Sys.println('BLESS: $manifestPath');
			return;
		}
		for (f in failures) Sys.println("FAIL " + f);
		for (f in fixed) Sys.println("FIXED " + f + " (BLESS=1 to require it)");
		if (failures.length > 0 || fixed.length > 0) {
			Sys.println('CssReftestCheck: ${failures.length} required failing, ${fixed.length} pending passing');
			Sys.exit(1);
		}
	}

	// (tests this engine is not for: paged media, and what needs a script or SVG)
	static function skipped(dir:String, t:Dynamic):Null<String> {
		var needs:Array<String> = t.needs != null ? t.needs : [];
		if (needs.contains("print") || paged(dir)) return "paged: printed pages, not a screen (stage 7)";
		if (needs.contains("script") || needs.contains("wait")) return "script: no JavaScript";
		return null;
	}

	static function paged(dir:String):Bool
		return dir.startsWith("css/css-page") || dir.startsWith("css/css-break") || dir.startsWith("css/css-gcpm") || dir == "css/CSS2/page-box"
			|| dir == "css/CSS2/pagination";

	// ---- a test and its references

	static function run(dir:String, t:Dynamic):{pass:Bool, why:String} {
		var path = '${WptPage.wpt}/$dir/${t.name}';
		try {
			var test = draw(path);
			if (t.type == "crash") return {pass: true, why: ""};
			var refs:Array<Array<Dynamic>> = t.refs != null ? t.refs : [];
			var fuzzy:Array<String> = t.fuzzy != null ? t.fuzzy : [];
			for (r in refs) {
				var refPath = haxe.io.Path.normalize('${WptPage.wpt}/$dir/${r[0]}');
				if (!FileSystem.exists(refPath)) return {pass: false, why: 'no reference ${r[0]}'};
				var ref = draw(refPath);
				var d = diff(test, ref);
				var allowed = tolerance(fuzzy, r[0]);
				var same = d.pixels == 0 || d.max >= allowed[0] && d.max <= allowed[1] && d.pixels >= allowed[2] && d.pixels <= allowed[3];
				if (r[1] == "match" && !same) return {pass: false, why: '${d.pixels} pixels differ (by up to ${d.max})'};
				if (r[1] == "mismatch" && same) return {pass: false, why: 'the same as ${r[0]}'};
			}
			return {pass: true, why: ""};
		} catch (e:Dynamic) {
			return {pass: false, why: 'error: ${Std.string(e).split("\n")[0]}'};
		}
	}

	static final drawn = new Map<String, Bytes>();

	// (a page's pixels, straight RGBA; references are drawn once a run)
	static function draw(path:String):Bytes {
		var cached = drawn.get(path);
		if (cached != null) return cached;
		var c = new Canvas(W, H);
		DocumentView.render(WptPage.parse(path), W, c, WptPage.options(path));
		var out = Bytes.alloc(W * H * 4);
		c.readPixels(out, 0, 0, W, H);
		if (path.indexOf("-ref") >= 0 || path.indexOf("/reference/") >= 0) drawn.set(path, out);
		return out;
	}

	static function diff(a:Bytes, b:Bytes):{pixels:Int, max:Int} {
		var pixels = 0, max = 0;
		var i = 0, n = a.length;
		while (i < n) {
			if (a.getInt32(i) != b.getInt32(i)) {
				var m = 0;
				for (k in 0...4) {
					var d = a.get(i + k) - b.get(i + k);
					if (d < 0) d = -d;
					if (d > m) m = d;
				}
				if (m > 0) {
					pixels++;
					if (m > max) max = m;
				}
			}
			i += 4;
		}
		return {pixels: pixels, max: max};
	}

	// (WPT's fuzzy: maxDifference and totalPixels ranges, for every reference or a named one)
	static function tolerance(fuzzy:Array<String>, ref:String):Array<Int> {
		var out = [0, 0, 0, 0];
		for (f in fuzzy) {
			var spec = f;
			var colon = f.indexOf(":");
			if (colon > 0 && f.substr(0, colon).indexOf("=") < 0 && f.substr(0, colon).indexOf(";") < 0) {
				if (!ref.endsWith(f.substr(0, colon))) continue;
				spec = f.substr(colon + 1);
			}
			var parts = spec.split(";");
			for (k in 0...parts.length) {
				var p = parts[k].trim();
				var eq = p.indexOf("=");
				var key = eq >= 0 ? p.substr(0, eq).trim() : k == 0 ? "maxDifference" : "totalPixels";
				var range = (eq >= 0 ? p.substr(eq + 1) : p).split("-");
				var lo = Std.parseInt(range[0].trim()) ?? 0, hi = range.length > 1 ? Std.parseInt(range[1].trim()) ?? lo : lo;
				if (range.length == 1) lo = 0;
				if (key == "maxDifference") {
					out[0] = lo;
					out[1] = hi;
				} else {
					out[2] = lo;
					out[3] = hi;
				}
			}
		}
		return out;
	}

	// ---- why a test is pending: the stage that brings it, by its directory, else by what its source uses

	static function reason(dir:String, t:Dynamic, why:String, was:Null<String>):String {
		if (was != null && was != "new" && was.startsWith(stage(dir, t) + ":")) return was;
		return '${stage(dir, t)}: $why';
	}

	static final STAGES = [
		"abspos" => "positioning", "positioning" => "positioning", "zindex" => "positioning", "zorder" => "positioning", "stacking-context" => "positioning",
		"floats" => "floats", "floats-clear" => "floats", "floats/crashtests" => "floats", "tables" => "tables", "fonts" => "fonts", "linebox" => "inline",
		"text" => "inline", "bidi-text" => "inline", "i18n/visuren" => "inline", "generated-content" => "generated", "generate" => "generated",
		"lists" => "generated", "ui" => "ui"
	];

	static function stage(dir:String, t:Dynamic):String {
		var short = dir.startsWith("css/CSS2/") ? dir.substr(9) : dir;
		var s = STAGES.get(short);
		if (s != null) return s;
		// (the test's source and its references': what either needs)
		var src = "";
		var refs:Array<Array<Dynamic>> = t.refs != null ? t.refs : [];
		for (f in [t.name].concat([for (r in refs) r[0]]))
			src += try File.getContent('${WptPage.wpt}/$dir/$f').toLowerCase() catch (_:Dynamic) "";
		var needs:Array<String> = t.needs != null ? t.needs : [];
		if (~/display\s*:\s*(inline-)?table|<table/.match(src)) return "tables";
		if (~/float\s*:\s*(left|right)|clear\s*:/.match(src)) return "floats";
		if (~/position\s*:\s*(absolute|fixed|sticky)/.match(src)) return "positioning";
		if (~/::?first-(line|letter)/.match(src)) return "inline";
		if (~/::?(before|after|marker)|counter|list-style|display\s*:\s*list-item|<li/.match(src)) return "generated";
		if (~/inline-block|vertical-align|line-height|white-space|text-align|text-indent|letter-spacing|word-spacing|direction|<br|text-transform/.match(src)) return "inline";
		// (ex and ch: helder.css computes them without the font's metrics yet)
		if (~/[0-9.](ex|ch)\b/.match(src)) return "fonts";
		if (needs.contains("svg") || needs.contains("image")) return "images";
		if (~/font(-family|-size|-weight|-style|-variant)?\s*:/.match(src)) return "fonts";
		return "blocks";
	}
}
