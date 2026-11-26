package helder.css;

import helder.css.CssTerm;

using Lambda;

// Terms written as CSSOM writes a specified value: keywords as the grammar
// has them, numbers in six significant digits, strings in double quotes,
// colours in Color 4's form, math functions as §10.12 serializes them;
// spaces between, a comma after its term.
class CssText {
	public static function term(t:CssTerm):String
		return switch t {
			case Keyword(k): k;
			case Ident(w): ident(w);
			case Number(v, integer): CssNumber.format(v, integer);
			case Percentage(v): CssNumber.format(v) + "%";
			case Dimension(v, u): CssNumber.format(v) + u;
			case Str(s): string(s);
			case Url(u, m): 'url(${[string(u)].concat(m).join(" ")})';
			case Color(c): CssColors.specified(c);
			case Calc(n, _, _): CssCalc.serialize(n);
			case Func(name, args): '$name(${join(args, term)})';
			case Brackets(open, args): open == "[" ? '[${join(args, term)}]' : '(${join(args, term)})';
			case Delim(d): d;
			case Raw(text): text;
			case Part(_, terms): join(terms, term);
		}

	public static function join(terms:Array<CssTerm>, f:CssTerm->String):String {
		var b = new StringBuf();
		terms = flat(terms);
		for (k in 0...terms.length) {
			var t = terms[k];
			switch t {
				case Delim(","): b.add(",");
				case _:
					if (k > 0) b.add(" ");
					b.add(f(t));
			}
		}
		return b.toString();
	}

	public static function ident(w:String):String {
		var b = new StringBuf();
		Serializer.ident(b, w);
		return b.toString();
	}

	public static function string(s:String):String {
		var b = new StringBuf();
		Serializer.string(b, s);
		return b.toString();
	}

	// (a shorthand's parts as their terms)
	public static function flat(terms:Array<CssTerm>):Array<CssTerm> {
		if (!terms.exists(t -> t.match(Part(_, _)))) return terms;
		var out = [];
		for (t in terms) switch t {
			case Part(_, ts): for (x in flat(ts)) out.push(x);
			case _: out.push(t);
		}
		return out;
	}

	// Terms split at their top-level commas (a list's layers).
	public static function layers(terms:Array<CssTerm>):Array<Array<CssTerm>> {
		var out = [[]];
		for (t in terms) if (t.match(Delim(","))) out.push([]) else out[out.length - 1].push(t);
		return out;
	}

	public static function unlayers(layers:Array<Array<CssTerm>>):Array<CssTerm> {
		var out:Array<CssTerm> = [];
		for (k in 0...layers.length) {
			if (k > 0) out.push(Delim(","));
			for (t in layers[k]) out.push(t);
		}
		return out;
	}
}
