package helder.css;

import helder.css.CssProperty;
import helder.css.CssTerm;

// A transition that starts (Transitions 1 §3): its property, its ends
// (computed, currentcolor resolved), its duration and delay in seconds,
// its easing; discrete: a property that doesn't interpolate, its value
// flipping halfway (transition-behavior: allow-discrete).
typedef CssTransitionStart = {
	property:CssProperty,
	from:Array<CssTerm>,
	to:Array<CssTerm>,
	duration:Float,
	delay:Float,
	easing:CssEasing,
	discrete:Bool
}

// Which properties of an element start transitions when its style
// changes (Transitions 1 §3, §4): the new style's transition-property
// list (all: every animatable longhand; a shorthand: its longhands; a
// name later in the list over one earlier), each with the duration,
// delay, timing function and behavior at its index (each list repeated),
// those whose combined duration is above 0, whose value changed, and that
// interpolate (or are discrete, with allow-discrete). No clock: what
// drives them (helder.ui's motion) asks `value` at a time.
//
//   for (t in CssTransition.starts(before, after)) motion.start(t);
//   CssTransition.value(t, 0.25);  // the terms a quarter second in
class CssTransition {
	public static function starts(before:CssStyle, after:CssStyle):Array<CssTransitionStart> {
		var names = after.terms(TransitionProperty);
		if (names.length == 1 && names[0].match(Keyword("none"))) return [];
		var lists = {
			names: CssText.layers(names),
			durations: CssText.layers(after.terms(TransitionDuration)),
			delays: CssText.layers(after.terms(TransitionDelay)),
			easings: CssText.layers(after.terms(TransitionTimingFunction)),
			behaviors: CssText.layers(after.terms(TransitionBehavior))
		};
		// (each longhand's index in the lists, the last naming it)
		var chosen = new Map<Int, Int>(), order = [];
		for (k in 0...lists.names.length) for (p in longhands(lists.names[k])) {
			if (!chosen.exists(p)) order.push(p);
			chosen.set(p, k);
		}
		var out = [];
		for (id in order) {
			var p:CssProperty = cast id, k = chosen[id];
			var duration = seconds(lists.durations[k % lists.durations.length]), delay = seconds(lists.delays[k % lists.delays.length]);
			if (Math.max(duration, 0) + delay <= 0) continue;
			var from = resolved(before, p), to = resolved(after, p);
			if (CssIntern.key(from) == CssIntern.key(to)) continue;
			var discrete = CssInterpolate.values(p, from, to, 0.5) == null;
			var behavior = lists.behaviors[k % lists.behaviors.length];
			if (discrete && !(behavior.length == 1 && behavior[0].match(Keyword("allow-discrete")))) continue;
			out.push({
				property: p,
				from: from,
				to: to,
				duration: Math.max(duration, 0),
				delay: delay,
				easing: CssEasing.of(lists.easings[k % lists.easings.length]),
				discrete: discrete
			});
		}
		return out;
	}

	// The transition's value at a time since it started, in seconds: the
	// easing's output for its progress, interpolated (a discrete one's ends
	// flipping halfway).
	public static function value(t:CssTransitionStart, time:Float):Array<CssTerm> {
		var x = t.duration == 0 ? (time >= t.delay ? 1.0 : 0.0) : (time - t.delay) / t.duration;
		if (x < 0) return t.from;
		if (x >= 1) return t.to;
		var p = t.easing.at(x);
		if (t.discrete) return CssInterpolate.discrete(t.property, t.from, t.to, p);
		return CssInterpolate.values(t.property, t.from, t.to, p) ?? (p < 0.5 ? t.from : t.to);
	}

	// (a list item's longhands: all's animatable ones, a shorthand's, a name's own; none or a name not known, none)
	static function longhands(item:Array<CssTerm>):Array<Int> {
		var name = switch item {
			case [Keyword(k)] | [Ident(k)]: k;
			case _: null;
		}
		if (name == null || name == "none") return [];
		if (name == "all")
			return [for (k in 0...CssProperties.COUNT) if (!CssProperties.logical(cast k) && CssProperties.animation(cast k) != 2) k];
		var p = CssProperties.of(name);
		if (p != null) return CssProperties.animation(p) == 2 ? [] : [p];
		var d = CssGrammars.property(name);
		if (d == null) return [];
		if (d.alias != null) return longhands([Ident(d.alias)]);
		return [
			for (l in CssShorthands.longhands(name)) {
				var q = CssProperties.of(l);
				if (q != null && !CssProperties.logical(q) && CssProperties.animation(q) != 2) (q : Int);
			}
		];
	}

	// (a time in seconds)
	static function seconds(t:Array<CssTerm>):Float
		return switch t {
			case [Dimension(v, "s")]: v;
			case [Dimension(v, "ms")]: v / 1000;
			case _: 0;
		}

	// (the value as it transitions: currentcolor as the element's colour, a
	// logical property's physical one's)
	public static function resolved(s:CssStyle, p:CssProperty):Array<CssTerm> {
		var t = s.terms(p);
		// (outline-color's auto is currentcolor's, to interpolate)
		if (p == OutlineColor && t.length == 1 && t[0].match(Keyword("auto"))) return s.terms(Color);
		var current = s.terms(Color);
		var color = current.length == 1 ? current[0] : null;
		return [for (x in t) switch x {
			case Color(c) if (c.keyword == "currentcolor" && color != null): color;
			case Func(f, args): Func(f, [for (a in args) switch a {
					case Color(c) if (c.keyword == "currentcolor" && color != null): color;
					case _: a;
				}]);
			case _: x;
		}];
	}
}
