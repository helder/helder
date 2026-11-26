package helder.css;

import helder.dom.Dom;
import helder.test.Test;

// CssModule.load: the names typed from the file (dashed ones camelCased),
// the sheets registered once, after those composed from, and cascaded
// after a document's own.
function tests() {
	describe("CssModule", () -> {
		test("names typed from the file, the sheets registered once and in order", () -> {
			final card = CssModule.load("helder/css/test-modules/card.module.css");
			var h = haxe.crypto.Md5.encode("src/helder/css/test-modules/card.module.css").substr(0, 6);
			equals(card.card, 'card_card_$h');
			equals(card.cardTitle, 'card_card-title_$h card_bold_$h');
			var count = CssModule.sheets().length;
			CssModule.load("helder/css/test-modules/card.module.css");
			equals(CssModule.sheets().length, count);
			// (base's before card's, which composes from it)
			var all = CssModule.sheets();
			var base = all.indexOf(helder.css.modules.Css_base_ada6d5.sheet), own = all.indexOf(helder.css.modules.Css_card_173e81.sheet);
			equals(base >= 0 && own == base + 1, true);
		});
		test("cascaded: a composed class's rules too", () -> {
			final card = CssModule.load("helder/css/test-modules/card.module.css");
			var doc = Dom.parse('<!doctype html><button class="${card.button}">b</button><p class="${card.cardTitle}">t</p>');
			var s = CssCascade.themed(doc, []);
			var b = s.computed(doc.getElementsByTagName("button").item(0)), p = s.computed(doc.getElementsByTagName("p").item(0));
			equals([b.text("color"), b.text("border-top-width"), b.text("margin-top")], ["rgb(200, 0, 0)", "1px", "0px"]);
			equals([p.text("font-size"), p.text("font-weight")], ["20px", "700"]);
		});
		test("helder dev's swap: the sheet replaced; changed names and errors said", () -> {
			final view = CssModule.load("helder/css/test-modules/view.module.css");
			var file = sys.FileSystem.fullPath("src/helder/css/test-modules/view.module.css"), root = sys.FileSystem.fullPath(Sys.getCwd());
			var m = CssScope.compile(file, {root: root}), text = sys.io.File.getContent(file);
			var names = [for (n in m.names) n.name + "=" + n.value].join("\n");
			var doc = Dom.parse('<!doctype html><div class="${view.wide}"></div>');
			inline function width()
				return CssCascade.themed(doc, []).computed(doc.getElementsByTagName("div").item(0)).text("width");
			equals(width(), "40px");
			var v = CssModule.version;
			equals(CssModule.reload(m.key, file, root, names, ".box { height: 10px } .wide { composes: box; width: 30px }"), "view.module.css swapped, nothing built");
			equals([width(), Std.string(CssModule.version > v)], ["30px", "true"]);
			equals(CssModule.reload(m.key, file, root, names, ".box { width: 1px } .tall { width: 2px }"),
				"view.module.css swapped, but its names changed (+tall -wide): rebuild to use them");
			var said = CssModule.reload(m.key, file, root, names, ".box { composes: nope } .wide { width: 5px }").split("\n");
			equals([StringTools.endsWith(said[0], "view.module.css:1:18: composes: no class .nope in this file"), said[1] == "view.module.css not swapped: the last sheet stays"], [true, true]);
			CssModule.reload(m.key, file, root, names, text);
			equals(width(), "40px");
		});
	});
}
