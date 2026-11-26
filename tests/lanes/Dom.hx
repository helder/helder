package lanes;

import lanes.Tools.*;

class Dom {
	public static final LANES:Array<Lane> = [
		{name: "dom", about: "helder.dom against html5lib's and WPT's parser tests, parse5 and expat", run: dom}
	];

	// (natively: the conformance check, each generated document's tree against
	// parse5's, then the XML parser's trees against expat's)
	static function dom() {
		var cp = cps(["src", "tests/dom"]);
		exe("bin/dom/DomConformanceCheck", cp.concat(["-main", "DomConformanceCheck"]));
		run(exePath("bin/dom/DomConformanceCheck", HOST), []);
		exe("bin/dom/DomDump", cp.concat(["-main", "DomDump"]));
		run(NODE, ["tests/dom/parse5.mjs", exePath("bin/dom/DomDump", HOST)]);
		exe("bin/dom/XmlCheck", cp.concat(["-main", "XmlCheck"]));
		run(exePath("bin/dom/XmlCheck", HOST), []);
	}
}
