package helder.css;

import helder.css.CssSheet;

// The user agent's sheets compiled at build time (CssTheme, from ua/*.css
// beside this file, as CssUserAgent parses them): a program styled by them
// and other compiled sheets alone (CssCascade.themed) links no CSS
// tokenizer or parser. The macros run where this class is used, so only
// such programs pay for them in build time (the HTML sheets are large);
// each sheet is its own class, linked only where it's used.
//
//   var styles = CssCascade.themed(doc, [CssUserAgentTheme.sheet(), CssTheme.file("theme.css")]);
class CssUserAgentTheme {
	static var quirky:Null<CssSheet>;

	// CssUserAgent.sheet()'s: HTML's rendering rules and print's defaults, quirks mode's on top.
	public static function sheet(quirks = false):CssSheet {
		var html = CssTheme.file("ua/html.css", UserAgent);
		if (!quirks) return html;
		return quirky ??= @:privateAccess new CssSheet(UserAgent, null, html.rules.concat(CssTheme.file("ua/html-quirks.css", UserAgent).rules));
	}

	// helder.ui's defaults as CSS for app trees (a draft for the port onto helder.dom: ua/README.md).
	public static function app():CssSheet
		return CssTheme.file("ua/app.css", UserAgent);
}
