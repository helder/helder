import haxe.Json;
import helder.css.CssMatcher;
import helder.css.CssSelector;
import helder.dom.Document;
import helder.dom.DocumentFragment;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.Node;
import sys.io.File;

// helder.css's selectors against WPT's dom/nodes/selectors.js
// (fixtures/selectors.json): its invalid selectors do not parse, its
// valid and scoped ones do (querySelector's: no @namespace declared).
// Then its valid ones matched as ParentNode-querySelector-All.html runs
// them on selectors.html parsed by helder.dom: setupSpecialElements' elements
// added, the four contexts (the document, the in-document #root, a
// detached clone, a fragment with a clone), each with the div
// verifyStaticList appends, the clones marked data-clone appended to the
// body before the in-document element's run; querySelectorAll's ids in
// tree order against the expected ones. The scoped ones are Selectors API
// 2's find() and refNodes, gone from the DOM: parsed alone. A pending
// case must fail, and fails the run once it passes.
class CssSelectorsCheck {
	// (name and context: why it fails)
	static final PENDING = [
		":target pseudo-class selector, matching the element referenced by the URL fragment identifier|document" => ":target never matches: a printed page has no URL fragment to follow",
		":target pseudo-class selector, matching the element referenced by the URL fragment identifier|element" => ":target never matches: a printed page has no URL fragment to follow",
	];

	static function main() {
		var f:Dynamic = Json.parse(File.getContent("tests/css/fixtures/selectors.json"));
		var failures = [], fixed = [], invalid:Array<Dynamic> = f.invalid, valid:Array<Dynamic> = f.valid, scoped:Array<Dynamic> = f.scoped;
		for (c in invalid)
			if (CssSelector.parse(c.selector) != null) failures.push('invalid, parsed: ${Json.stringify(c.selector)} (${c.name})');
		var seen = new Map<String, Bool>();
		for (c in valid.concat(scoped)) {
			var s:String = c.selector;
			if (seen.exists(s)) continue;
			seen.set(s, true);
			if (CssSelector.parse(s) == null) failures.push('valid, not parsed: ${Json.stringify(s)} (${c.name})');
		}
		Sys.println('CssSelectorsCheck: ${invalid.length} invalid, ${[for (k in seen.keys()) k].length} distinct valid selectors parsed or not');

		var doc = Dom.parse(File.getContent("tests/css/fixtures/selectors.html"));
		var element = doc.getElementById("root");
		setup(doc, element);
		var outOfScope:Element = cast element.cloneNode(true);
		var n:Null<Node> = outOfScope;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE) (cast n : Element).setAttribute("data-clone", "");
			n = after(n, outOfScope);
		}
		var detached:Element = cast element.cloneNode(true);
		var fragment = doc.createDocumentFragment();
		fragment.appendChild(element.cloneNode(true));
		// (verifyStaticList's: a div appended to each context)
		doc.body.appendChild(doc.createElement("div"));
		detached.appendChild(doc.createElement("div"));
		fragment.appendChild(doc.createElement("div"));
		element.appendChild(doc.createElement("div"));

		var runs = 0, passed = 0;
		function context(name:String, root:Node, scope:Null<Element>) {
			for (c in valid) {
				var types:Array<String> = c.testType, exclude:Array<String> = c.exclude == null ? [] : c.exclude;
				if (!types.contains("qsa") || exclude.contains(name) || exclude.contains("html")) continue;
				runs++;
				var list = CssSelector.parse(c.selector);
				var ids:Array<Null<String>> = list == null ? ["(not parsed)"] : [
					for (e in CssMatcher.query([for (s in list) if (s.pseudo == null) s], root, scope))
						e.getAttribute("id")
				];
				var expect:Array<String> = c.expect;
				var ok = ids.join("\x00") == expect.join("\x00") && ids.length == expect.length;
				var key = '${c.name}|$name', pending = PENDING.get(key);
				if (ok) passed++;
				if (ok && pending != null) fixed.push('$key passes now (pending: $pending)');
				if (!ok && pending == null)
					failures.push('$name: ${c.name}: ${Json.stringify(c.selector)}\n    expected ${Json.stringify(expect)}\n    matched  ${Json.stringify(ids)}');
			}
		}
		context("document", doc, null);
		context("detached", detached, detached);
		context("fragment", fragment, null);
		doc.body.appendChild(outOfScope);
		context("element", element, element);
		Sys.println('CssSelectorsCheck: querySelectorAll in 4 contexts: $passed of $runs as expected, ${[for (k in PENDING.keys()) k].length} pending');

		for (x in failures)
			Sys.println("FAIL " + x);
		for (x in fixed)
			Sys.println("FIXED " + x);
		if (failures.length + fixed.length > 0) {
			Sys.println('CssSelectorsCheck: ${failures.length} failing, ${fixed.length} pending passing');
			Sys.exit(1);
		}
		Sys.println("CssSelectorsCheck: all pass");
	}

	// (ParentNode-querySelector-All.js's setupSpecialElements)
	static function setup(doc:Document, parent:Element) {
		parent.appendChild(doc.createElement("null"));
		parent.appendChild(doc.createElement("undefined"));
		var anyNS = doc.createElement("div"), noNS = doc.createElement("div");
		anyNS.id = "any-namespace";
		noNS.id = "no-namespace";
		for (box in [anyNS, noNS]) {
			var prefix = box.id;
			var divs = [
				doc.createElement("div"),
				doc.createElementNS("http://www.w3.org/1999/xhtml", "div"),
				doc.createElementNS("", "div"),
				doc.createElementNS("http://www.example.org/ns", "div")
			];
			for (k in 0...4) {
				divs[k].setAttribute("id", '$prefix-div${k + 1}');
				box.appendChild(divs[k]);
			}
		}
		parent.appendChild(anyNS);
		parent.appendChild(noNS);
		doc.getElementById("attr-presence-i1").setAttributeNS("http://www.example.org/ns", "title", "");
	}

	static function after(n:Node, root:Node):Null<Node> {
		if (n.firstChild != null) return n.firstChild;
		while (n != root) {
			if (n.nextSibling != null) return n.nextSibling;
			n = n.parentNode;
		}
		return null;
	}
}
