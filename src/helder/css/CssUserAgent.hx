package helder.css;

import helder.css.CssSheet;

// The user agent's style sheets (CssUserAgentData: HTML's rendering rules
// and print's defaults), parsed once: every document's, quirks mode's on
// top, and the presentational hints HTML writes as CSS.
class CssUserAgent {
	static var standard:Null<CssSheet>;
	static var quirky:Null<CssSheet>;
	static var hinted:Null<CssSheet>;

	public static function sheet(quirks = false):CssSheet {
		if (!quirks) return standard ??= CssSheet.parse(CssUserAgentData.base, UserAgent);
		return quirky ??= CssSheet.parse(CssUserAgentData.base + "\n" + CssUserAgentData.quirks, UserAgent);
	}

	// (author origin, as presentational hints are: the cascade gives them specificity zero)
	public static function hints():CssSheet
		return hinted ??= CssSheet.parse(CssUserAgentData.hints, Author);
}
