import haxe.Json;
import helder.css.CssSelector;
import sys.io.File;

// helder.css's selectors against WPT's dom/nodes/selectors.js
// (fixtures/selectors.json, #300's extraction): its invalid selectors
// do not parse, its valid and scoped ones do (querySelector's: no
// @namespace declared). Matching them on selectors.html waits for helder.dom.
class CssSelectorsCheck {
	static function main() {
		var f:Dynamic = Json.parse(File.getContent("tests/css/fixtures/selectors.json"));
		var failures = [], invalid:Array<Dynamic> = f.invalid, valid:Array<Dynamic> = f.valid, scoped:Array<Dynamic> = f.scoped;
		for (c in invalid)
			if (CssSelector.parse(c.selector) != null) failures.push('invalid, parsed: ${Json.stringify(c.selector)} (${c.name})');
		var seen = new Map<String, Bool>();
		for (c in valid.concat(scoped)) {
			var s:String = c.selector;
			if (seen.exists(s)) continue;
			seen.set(s, true);
			if (CssSelector.parse(s) == null) failures.push('valid, not parsed: ${Json.stringify(s)} (${c.name})');
		}
		Sys.println('CssSelectorsCheck: ${invalid.length} invalid, ${[for (k in seen.keys()) k].length} distinct valid selectors');
		for (x in failures)
			Sys.println("FAIL " + x);
		if (failures.length > 0) {
			Sys.println('CssSelectorsCheck: ${failures.length} failing');
			Sys.exit(1);
		}
		Sys.println("CssSelectorsCheck: all pass");
	}
}
