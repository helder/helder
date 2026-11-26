import helder.css.CssCascade;
import helder.css.CssTheme;
import helder.dom.Dom;

// The theme probe (the css lane): a document styled with sheets compiled
// at build time (CssTheme) alone, var() substituted when computed. Built
// with -dce full and symbols, its symbols hold no CSS tokenizer or parser;
// with -D css.parse, its first sheet parsed when it runs instead, they
// hold them (the check's control). Prints what it computed.
class ThemeProbe {
	static inline final FIRST = "html { --hover: #fafafa } p { color: green }";

	static function main() {
		var doc = Dom.parse("<!doctype html><div class=list><p class=item>a</p><p class=item><span class=button>b</span></p></div>");
		var styles = CssCascade.themed(doc, [
			#if css.parse helder.css.CssSheet.parse(FIRST, Author) #else CssTheme.sheet(FIRST) #end,
			CssTheme.file("theme/theme.css")
		],
			{media: {type: "screen", width: 800, height: 600}});
		var items = doc.getElementsByClassName("item"), button = doc.getElementsByClassName("button").item(0);
		var second = items.item(1), first = items.item(0);
		for (line in [
			styles.computed(first).text("display"),
			styles.computed(first).text("font-size"),
			styles.computed(first).text("margin-left"),
			styles.computed(first).text("border-top-width"),
			styles.computed(second).text("border-top-width"),
			styles.computed(second).text("color"),
			styles.computed(button).text("color"),
			styles.computed(button).text("padding-left"),
			styles.computed(button).text("padding-top")
		])
			Sys.println(line);
	}
}
