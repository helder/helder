import helder.css.CssCascade;
import helder.css.CssUserAgentTheme;
import helder.dom.Dom;

// The user agent's sheet compiled at build time (the css lane): a
// document styled by it alone (CssCascade.themed), its values printed.
// Built with -dce full and symbols, its symbols hold no CSS tokenizer or
// parser; with -D css.parse, the same document styled when it runs
// (CssCascade.styles, which parses its <style>s), they hold them (the
// check's control), the values the same.
class UaProbe {
	static function main() {
		var doc = Dom.parse("<!doctype html><h1 id=h>a</h1><p id=p>b <a id=a href=x>c</a></p><ul><li id=li>d</li></ul><span id=s>e</span>");
		var styles = #if css.parse CssCascade.styles(doc) #else CssCascade.themed(doc, [CssUserAgentTheme.sheet()]) #end;
		inline function v(id:String, p:String)
			return styles.computed(doc.getElementById(id)).text(p);
		for (line in [
			v("h", "font-size"), v("h", "font-weight"), v("p", "margin-top"), v("p", "display"), v("s", "display"), v("li", "display"),
			v("a", "text-decoration-line"), v("a", "color"), v("h", "bookmark-level")
		])
			Sys.println(line);
	}
}
