package helder.css;

import helder.css.CssComputed;
import helder.css.CssTerm;

using Lambda;

// A property's value read against its grammar, written in CSSOM's
// canonical form, and computed as far as needs no layout.
class CssValues {
	public static final DEFAULT:CssComputeContext = {
		fontSize: 16,
		parentFontSize: 16,
		rootFontSize: 16,
		viewport: {width: 800, height: 600},
		color: "rgb(0, 0, 0)"
	};

	// A declaration's value for a property, null when it is not one of the
	// property's grammar (an unknown property's, too).
	public static function parse(property:String, text:String):Null<CssSpecified>
		return read(property, Css.values(text));

	// A declaration's component values for a property, as parse.
	public static function read(property:String, values:Array<CssValue>):Null<CssSpecified> {
		var custom = StringTools.startsWith(property, "--");
		var name = custom ? property : Css.lower(property);
		values = trim(values);
		if (custom) return Unresolved(Css.serialize(values));
		if (CssGrammars.property(name) == null || values.length == 0) return null;
		if (values.length == 1) switch values[0] {
			case Token(t): switch t.kind {
					case Ident(w) if (["initial", "inherit", "unset", "revert", "revert-layer"].contains(Css.lower(w))): return Wide(Css.lower(w));
					case _:
				}
			case _:
		}
		if (substitutes(values)) return arbitrary(values) ? Unresolved(Css.serialize(values)) : null;
		// (flex: three numbers are grow, shrink and a basis, which a number but 0 can't be)
		if (name == "flex") {
			var items = [for (v in values) if (!isSpace(v)) v];
			if (items.length == 3 && items.foreach(v -> v.match(Token(_.kind => Number(_, _, _)))) && !items[2].match(Token(_.kind => Number(0, _, _)))) return null;
		}
		var terms = CssMatch.property(name, values);
		if (terms == null || !CssCanonical.valid(name, terms)) return null;
		// (a shorthand's value is one only if its longhands can be had from it)
		if (CssShorthands.isShorthand(name) && CssShorthands.expand(name, terms) == null) return null;
		return Terms(terms);
	}

	// The specified value as CSSOM serializes it (CssCanonical's forms).
	public static function serialize(property:String, v:CssSpecified):String
		return switch v {
			case Wide(k): k;
			case Unresolved(text): text;
			case Terms(terms) if (CssShorthands.isShorthand(Css.lower(property))):
				var name = Css.lower(property);
				var longhands = CssShorthands.expand(name, terms);
				longhands == null ? "" : CssShorthands.serialize(name, [for (l => t in longhands) l => serialize(l, Terms(t))], false);
			case Terms(terms): CssText.join(CssCanonical.terms(Css.lower(property), terms), CssText.term);
		}

	// The computed value, as getComputedStyle writes it where no layout is
	// needed; null where it can't say (an inherited value, a prose initial
	// value, a value to substitute).
	public static function compute(property:String, v:CssSpecified, ?ctx:CssComputeContext):Null<String> {
		var c = ctx ?? DEFAULT;
		var name = Css.lower(property);
		var p = CssGrammars.property(name);
		return switch v {
			// (initial is the initial value; unset that where the property doesn't inherit)
			case Wide("initial") | Wide("unset") if (p != null && p.initial != null && (v.match(Wide("initial")) || p.inherited == false)):
				var initial = parse(name, p.initial);
				initial == null || initial.match(Wide(_)) ? null : compute(name, initial, c);
			case Wide(_) | Unresolved(_): null;
			case Terms(terms) if (CssShorthands.isShorthand(name)):
				var longhands = CssShorthands.expand(name, terms);
				if (longhands == null) return null;
				var texts = new Map<String, String>();
				for (l => t in longhands) {
					var x = compute(l, Terms(t), c);
					if (x == null) return null;
					texts.set(l, x);
				}
				CssShorthands.serialize(name, texts, true);
			case Terms(terms):
				var computed = CssComputed.terms(name, CssCanonical.terms(name, terms), c);
				CssText.join(CssCanonical.terms(name, computed), t -> text(t, c));
		}
	}

	// Computed terms as getComputedStyle writes them, colours resolved in the context.
	public static function written(property:String, terms:Array<CssTerm>, ctx:CssComputeContext):String
		return CssText.join(CssCanonical.terms(property, terms), t -> text(t, ctx));

	static function text(t:CssTerm, ctx:CssComputeContext):String
		return switch t {
			case Color(c): CssColors.computed(c, ctx.color, {fontSize: ctx.fontSize, rootFontSize: ctx.rootFontSize, viewport: ctx.viewport}) ?? CssColors.specified(c);
			case Func(name, args): '$name(${CssText.join(args, a -> text(a, ctx))})';
			case Brackets("[", args): '[${CssText.join(args, a -> text(a, ctx))}]';
			case _: CssText.term(t);
		}

	static function trim(values:Array<CssValue>):Array<CssValue> {
		var a = 0, z = values.length;
		while (a < z && isSpace(values[a])) a++;
		while (z > a && isSpace(values[z - 1])) z--;
		return values.slice(a, z);
	}

	static function isSpace(v:CssValue):Bool
		return switch v {
			case Token(t): t.kind.match(Whitespace);
			case _: false;
		}

	// (var() names something, env() an ident; a fallback, all after the
	// first comma, with a {} block is that block alone: Values 5 §3)
	static function arbitrary(values:Array<CssValue>):Bool {
		for (v in values) switch v {
			case Function(name, inner, _, _):
				var n = Css.lower(name);
				if (n == "var" || n == "env") {
					var items = [for (x in inner) if (!isSpace(x)) x];
					var comma = -1;
					for (k in 0...items.length) if (comma < 0 && isComma(items[k])) comma = k;
					var first = comma < 0 ? items : items.slice(0, comma);
					if (first.length == 0) return false;
					if (n == "env" && !first[0].match(Token(_.kind => Ident(_)) | Function(_, _, _, _))) return false;
					if (comma >= 0) {
						var fallback = items.slice(comma + 1);
						if (fallback.length > 1 && Lambda.exists(fallback, isCurly)) return false;
					}
					if (first.length > 1 && Lambda.exists(first, isCurly)) return false;
					// (a var() of an empty {} block names nothing)
					if (first.length == 1 && first[0].match(Block(_, [], _))) return false;
				}
				if (!arbitrary(inner)) return false;
			case Block(_, inner, _):
				if (!arbitrary(inner)) return false;
			case _:
		}
		return true;
	}

	static function isComma(v:CssValue):Bool
		return switch v {
			case Token(t): t.kind.match(Comma);
			case _: false;
		}

	static function isCurly(v:CssValue):Bool
		return switch v {
			case Block(o, _, _): o.kind.match(OpenCurly);
			case _: false;
		}

	// (var() or env() anywhere: the value is checked once substituted)
	static function substitutes(values:Array<CssValue>):Bool {
		for (v in values) switch v {
			case Function(name, inner, _, _):
				var n = Css.lower(name);
				if (n == "var" || n == "env" || substitutes(inner)) return true;
			case Block(_, inner, _):
				if (substitutes(inner)) return true;
			case _:
		}
		return false;
	}
}
