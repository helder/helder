import helder.async.Async;
import helder.css.CssCascade;
import helder.css.CssModule;
import helder.dom.Dom;

// A console program for the dev loop with a CSS module (the cli lane's
// css-module mode): an element styled through cards.module.css; under
// helder dev an edit to the file swaps the module's sheet without a build.
// A line when the element's width changes, looked at ten times a second.
class Cards {
	static function main() {
		final cards = CssModule.load("cards.module.css");
		var doc = Dom.parse('<!doctype html><div class="${cards.card}"></div>');
		var last = "";
		Async.main(_ -> while (alive()) {
			var w = CssCascade.themed(doc, []).computed(doc.getElementsByTagName("div").item(0)).text("width");
			if (w != last) Sys.println('cards: width ${last = w}');
			#if hxmc.dev
			helder.dev.Hot.framed();
			#end
			Async.delay(0.1);
		});
	}

	// (the dev server's messages: false once this build handed over)
	static function alive():Bool {
		#if hxmc.dev
		return helder.dev.Hot.poll();
		#else
		return true;
		#end
	}
}
