package helder.css;

import helder.css.CssSheet;
#if macro
import haxe.io.Path;
import haxe.macro.Context;
#end

// The user agent's style sheets, from ua/*.css beside this file (ua.mjs
// writes the HTML ones): HTML's rendering rules and print's defaults for
// every document, quirks mode's on top, the presentational hints HTML
// writes as CSS; and app.css, helder.ui's defaults for app trees. Each is
// parsed when first asked (CssCascade.styles parses a document's own CSS
// anyway); CssUserAgentTheme has them compiled at build time.
class CssUserAgent {
	static var standard:Null<CssSheet>;
	static var quirky:Null<CssSheet>;
	static var hinted:Null<CssSheet>;

	public static function sheet(quirks = false):CssSheet {
		if (!quirks) return standard ??= CssSheet.parse(text("ua/html.css"), UserAgent);
		return quirky ??= CssSheet.parse(text("ua/html.css") + "\n" + text("ua/html-quirks.css"), UserAgent);
	}

	// (author origin, as presentational hints are: the cascade gives them specificity zero)
	public static function hints():CssSheet
		return hinted ??= CssSheet.parse(text("ua/html-hints.css"), Author);

	// helder.ui's defaults as CSS for app trees (a draft for the port onto helder.dom: ua/README.md).
	public static function app():CssSheet
		return CssSheet.parse(text("ua/app.css"), UserAgent);

	// (a CSS file beside this one, as a string constant)
	static macro function text(file:String):haxe.macro.Expr {
		var path = Path.join([Path.directory(Context.getPosInfos(Context.currentPos()).file), file]);
		Context.registerModuleDependency(Context.getLocalModule(), path);
		return macro $v{sys.io.File.getContent(path)};
	}
}
