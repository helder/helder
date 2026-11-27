import haxe.DynamicAccess;
import haxe.Json;
import helder.ui.box.DocumentView;
import helder.ui.box.Geometry;
import helder.ui.box.GeometryDiff;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The reftests' pages laid out by helder.ui.box against Chromium's
// layout of them, box by box (helder.ui.box.GeometryDiff): each test
// CssReftestCheck draws on a screen, at 800 by 600, against its snapshot
// by geometry.mjs (GEOMETRY, its directory; else bin/css/geometry/current).
// Not a gate: it says where a test's layout first differs, its likely
// cause. Writes bin/css/geometry/report.md (counts against the reftests'
// results, a line a test) and a JSON a test under bin/css/geometry/results;
// a run of a few tests prints each one's differences.
//
//   CssGeometryCheck [filter...]   (a directory or test name's part: those alone)
//   GEOMETRY_TOLERANCE=1 CssGeometryCheck ...   (px; 0.5 by default)
class CssGeometryCheck {
	static final here = "tests/css";
	static inline var W = 800;
	static inline var H = 600;
	static inline var OUT = "bin/css/geometry";
	// (at most this many tests: each one's differences printed)
	static inline var SHOWN = 5;

	static function main() {
		var filters = Sys.args();
		if (filters[0] == "--fonts") return CssReftestCheck.fonts();
		var tolerance = Std.parseFloat(Sys.getEnv("GEOMETRY_TOLERANCE") ?? "0.5");
		var snapshots = Sys.getEnv("GEOMETRY") ?? (FileSystem.exists('$OUT/current') ? File.getContent('$OUT/current').trim() : null);
		if (snapshots == null || !FileSystem.exists(snapshots)) {
			Sys.println('CssGeometryCheck: no snapshots (node tests/css/geometry.mjs)');
			Sys.exit(1);
		}
		var fixtures:Dynamic = Json.parse(File.getContent('$here/fixtures/reftests.json'));
		var manifest:DynamicAccess<Dynamic> = Json.parse(File.getContent('$here/reftest-manifest.json')).cases;
		var dirs:DynamicAccess<Dynamic> = fixtures.directories;
		var names = [for (k in dirs.keys()) k];
		names.sort(Reflect.compare);
		var todo = [];
		for (dir in names) {
			var tests:Array<Dynamic> = dirs[dir].tests ?? [];
			for (t in tests) {
				var id = '$dir/${t.name}';
				if (filters.length > 0 && !Lambda.exists(filters, f -> id.indexOf(f) >= 0)) continue;
				var entry:Dynamic = manifest[id];
				var skip = entry != null ? entry.skip : CssReftestCheck.skipped(dir, t);
				if (skip != null || dir.startsWith("css/css-gcpm") || CssReftestCheck.printed(dir, t)) continue;
				todo.push({dir: dir, id: id, reftest: entry == null ? "new" : entry.pending != null ? "pending" : "pass"});
			}
		}
		var t0 = haxe.Timer.stamp();
		var lines = [], stats = new Map<String, Array<Int>>();
		var counts = {pass: [0, 0], pending: [0, 0], other: [0, 0], none: 0, error: 0};
		for (t in todo) {
			var file = '$snapshots/${t.id}.json';
			var st = stats.get(t.dir);
			if (st == null) stats.set(t.dir, st = [0, 0, 0]);
			if (!FileSystem.exists(file)) {
				counts.none++;
				st[2]++;
				lines.push('- ${t.id}: no snapshot');
				continue;
			}
			var d = try GeometryDiff.of(Geometry.parse(File.getContent(file)), layout('${WptPage.wpt}/${t.id}'), tolerance) catch (e:Dynamic) {
				counts.error++;
				st[2]++;
				lines.push('- ${t.id}: error: ${Std.string(e).split("\n")[0]}');
				continue;
			};
			var k = d.match ? 0 : 1;
			st[k]++;
			(t.reftest == "pass" ? counts.pass : t.reftest == "pending" ? counts.pending : counts.other)[k]++;
			lines.push('- ${t.id} (${t.reftest}): ${d.match ? "matches" : summary(d)}');
			var at = '$OUT/results/${t.id}.json';
			FileSystem.createDirectory(haxe.io.Path.directory(at));
			File.saveContent(at, d.toJson());
			if (todo.length <= SHOWN) Sys.println('${t.id} (reftest ${t.reftest}):\n${d.describe()}\n');
		}
		var seconds = haxe.Timer.stamp() - t0;
		for (dir in names) {
			var s = stats.get(dir);
			if (s != null) Sys.println('${dir.rpad(" ", 44)} ${Std.string(s[0]).lpad(" ", 4)} of ${Std.string(s[0] + s[1]).lpad(" ", 4)} match${s[2] > 0 ? ', ${s[2]} not compared' : ""}');
		}
		var matched = counts.pass[0] + counts.pending[0] + counts.other[0], ran = matched + counts.pass[1] + counts.pending[1] + counts.other[1];
		var head = [
			'# helder.ui.box against Chromium, box by box',
			'',
			'$matched of $ran tests match within $tolerance px; ${counts.none} without a snapshot, ${counts.error} failed to lay out (${Math.round(seconds * 10) / 10} s, ${ran > 0 ? Math.round(seconds * 1000 / ran * 10) / 10 : 0} ms a test).',
			'',
			'| reftest | geometry matches | differs |',
			'| --- | --- | --- |',
			'| passing | ${counts.pass[0]} | ${counts.pass[1]} |',
			'| pending | ${counts.pending[0]} | ${counts.pending[1]} |',
			'| new | ${counts.other[0]} | ${counts.other[1]} |',
			''
		];
		Sys.println('all: ${head[2]}');
		Sys.println('passing reftests: ${counts.pass[0]} match, ${counts.pass[1]} differ; pending: ${counts.pending[0]} match, ${counts.pending[1]} differ');
		if (filters.length == 0 || todo.length > SHOWN) {
			FileSystem.createDirectory(OUT);
			File.saveContent('$OUT/report.md', head.concat(lines).join("\n") + "\n");
			Sys.println('report: $OUT/report.md');
		}
	}

	// (a test's first difference in a line, the report's)
	static function summary(d:GeometryDiff):String
		return d.first == null ? 'differs' : GeometryDiff.line(d.first, d.tolerance) + ' (${d.differences.length} of ${d.nodes} differ)';

	public static function layout(path:String):Geometry {
		var v = DocumentView.html(WptPage.parse(path), WptPage.options(path));
		v.layout(W, H);
		return Geometry.of(v);
	}
}
