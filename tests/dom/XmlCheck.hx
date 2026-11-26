import helder.dom.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.dom's XML parser against expat's trees (tests/dom/fixtures/xml:
// WPT's CSS2 .xht and .svg files and the cases import-xml.py writes; one
// expat refuses must be refused), natively:
//
//   bin/dom/XmlCheck                 the fixtures
//   bin/dom/XmlCheck --dir <dir>     every .xht, .xml and .svg under dir parsed: each without an error
class XmlCheck {
	static function main() {
		var args = Sys.args();
		if (args[0] == "--dir") {
			directory(args[1]);
			return;
		}
		var dir = "tests/dom/fixtures/xml";
		var names = [for (f in FileSystem.readDirectory(dir)) if (f.endsWith(".tree")) f.substr(0, f.length - 5)];
		names.sort(Reflect.compare);
		var failures = [];
		for (n in names) {
			var want = File.getContent('$dir/$n.tree');
			var errors = [];
			var doc = Dom.parseXml(File.getContent('$dir/$n'), errors);
			if (want == "error\n") {
				if (errors.length == 0) failures.push('$n: parsed, expat refuses it');
				continue;
			}
			if (errors.length > 0) {
				failures.push('$n: ${errors[0].code} at ${errors[0].offset}');
				continue;
			}
			var got = Dump.xml(doc);
			if (got != want) {
				var g = got.split("\n"), w = want.split("\n"), k = 0;
				while (k < g.length && g[k] == w[k])
					k++;
				failures.push('$n: line ${k + 1}: ${g[k]}, not ${w[k]}');
			}
		}
		for (f in failures)
			Sys.println("FAIL " + f);
		Sys.println('XmlCheck: ${names.length - failures.length} of ${names.length} documents as expat reads them');
		if (failures.length > 0) Sys.exit(1);
	}

	static function directory(root:String) {
		var files = 0, refused = [];
		function walk(d:String)
			for (f in FileSystem.readDirectory(d)) {
				var p = '$d/$f';
				if (FileSystem.isDirectory(p)) walk(p) else if (f.endsWith(".xht") || f.endsWith(".xml") || f.endsWith(".svg")) {
					var text = try File.getContent(p) catch (_) continue;
					files++;
					var errors = [];
					Dom.parseXml(text, errors);
					if (errors.length > 0) refused.push('$p: ${errors[0].code} at ${errors[0].offset}');
				}
			}
		walk(root);
		for (r in refused)
			Sys.println("REFUSED " + r);
		Sys.println('XmlCheck: ${files - refused.length} of $files files parsed without an error');
	}
}
