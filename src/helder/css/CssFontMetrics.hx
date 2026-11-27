package helder.css;

// The first available font's metrics for an element (Values 4 §6.1.1), in
// px at its font size: what ex, ch, cap and ic are, and line-height:
// normal. The engine that has fonts gives them (CssStyles.metrics).
typedef CssFontMetrics = {
	// x-height (ex)
	ex:Float,
	// the advance of "0" (ch)
	ch:Float,
	// the cap height (cap)
	cap:Float,
	// the advance of "水" (ic)
	ic:Float,
	// line-height: normal (ascent, descent and line gap)
	lineHeight:Float
}

// An element's font, as its computed values: what CssStyles.metrics is asked
typedef CssFontQuery = {
	family:Array<CssTerm>,
	// px
	size:Float,
	weight:Array<CssTerm>,
	style:Array<CssTerm>,
	stretch:Array<CssTerm>,
	variations:Array<CssTerm>,
	opticalSizing:Array<CssTerm>
}
