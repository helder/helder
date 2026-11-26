package reference;

// #321's cascade as it was merged (bee738a8), frozen: the oracle that
// computed styles through CssStyle's groups are checked against.

import helder.css.*;
import reference.RefSheet;
import reference.RefStyle;
import reference.RefStyles;
import reference.RefCascade;
import reference.RefHints;
import helder.css.CssTerm;
import helder.css.CssCalc;
import helder.css.CssComputed;


// The user agent's style sheets (CssUserAgentData: HTML's rendering rules
// and print's defaults), parsed once: every document's, quirks mode's on
// top, and the presentational hints HTML writes as CSS.
class RefUserAgent {
	static var standard:Null<RefSheet>;
	static var quirky:Null<RefSheet>;
	static var hinted:Null<RefSheet>;

	public static function sheet(quirks = false):RefSheet {
		if (!quirks) return standard ??= RefSheet.parse(RefUserAgentData.base, UserAgent);
		return quirky ??= RefSheet.parse(RefUserAgentData.base + "\n" + RefUserAgentData.quirks, UserAgent);
	}

	// (author origin, as presentational hints are: the cascade gives them specificity zero)
	public static function hints():RefSheet
		return hinted ??= RefSheet.parse(RefUserAgentData.hints, Author);
}
