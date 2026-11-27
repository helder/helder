import haxe.Json;
import helder.dom.Dom;
import helder.ui.box.DocumentView;
import helder.ui.box.Geometry;
import helder.ui.box.GeometryDiff;
import sys.io.Process;

// Chromium's geometry of a page of HTML and CSS, for properties to hold
// helder's layout against: one headless browser for the process
// (geometry.mjs --serve, its fonts and URL as the reftests' snapshots
// have them; needs bin/css/CssGeometryCheck for the fonts), a page
// answered at a time, each kept by its text (a shrink asks again).
//
//   var d = Chromium.compare('<div style="width: 50px">...</div>');
//   assert(d.match, d.describe());
class Chromium {
	// (the URL both lay the page out at: WPT's host, so /fonts/ahem.css is found)
	public static inline var URL = WptPage.HOST + "__helder/case.html";

	static var server:Null<Process> = null;
	static final answers = new Map<String, Geometry>();

	public static function geometry(html:String):Geometry {
		var known = answers.get(html);
		if (known != null) return known;
		server ??= new Process("node", ["tests/css/geometry.mjs", "--serve"]);
		server.stdin.writeString(Json.stringify({html: html}) + "\n");
		server.stdin.flush();
		var line = server.stdout.readLine();
		var o:Dynamic = Json.parse(line);
		if (o.error != null) throw 'Chromium: ${o.error}';
		var g = Geometry.parse(line);
		answers.set(html, g);
		return g;
	}

	// helder's geometry of the same page, at 800 by 600
	public static function helder(html:String):Geometry {
		var o = WptPage.options('${WptPage.wpt}/fonts/ahem.css');
		o.url = URL;
		var v = DocumentView.html(Dom.parse(html), o);
		v.layout(800, 600);
		return Geometry.of(v);
	}

	public static function compare(html:String, tolerance = 0.5):GeometryDiff
		return GeometryDiff.of(geometry(html), helder(html), tolerance);

	public static function close() {
		if (server == null) return;
		server.stdin.close();
		server.exitCode();
		server.close();
		server = null;
	}
}
