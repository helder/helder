package helder.ui.fast;

import helder.css.CssTerm;

using StringTools;

// A grid's values as CSS writes them, read into the terms the cascade
// computes for them (what GridFlow reads, BoxRare's), by a parser of its
// own: tracks ("1fr 200px", "repeat(3, 1fr)", "[a] minmax(100px, 1fr)",
// "fit-content(200px)"), areas ("'head head' 'side main'"), auto-flow
// ("row dense"), an item's lines ("1 / 3", "span 2", an area's name). No
// helder.css tokenizer or parser.
class GridTerms {
	// (the grammar's keywords: the rest names, idents)
	static final KEYWORDS = [
		"auto", "none", "min-content", "max-content", "span", "dense", "row", "column", "auto-fill", "auto-fit", "subgrid", "masonry"
	];

	// A track list (grid-template-rows and -columns, grid-auto-rows and -columns).
	public static function tracks(s:String):Array<CssTerm>
		return new GridTerms(s).list(-1);

	// grid-template-areas: its rows' strings, or none.
	public static function areas(s:String):Array<CssTerm> {
		var t = new GridTerms(s).list(-1);
		return t.length == 0 ? [Keyword("none")] : t;
	}

	// grid-auto-flow: row's left out where dense is (as computed).
	public static function flow(s:String):Array<CssTerm> {
		var t = new GridTerms(s).list(-1);
		var dense = Lambda.exists(t, x -> x.match(Keyword("dense")));
		return dense ? [for (x in t) if (!x.match(Keyword("row"))) x] : t;
	}

	// An item's lines on an axis (grid-row, grid-column): start and end.
	public static function lines(s:String):Array<Array<CssTerm>> {
		var parts = s.split("/");
		var start = line(parts[0]), end = parts.length > 1 ? line(parts[1]) : alone(start);
		return [start, end];
	}

	// grid-area: row start, column start, row end, column end (each left out its start's name, else auto).
	public static function area(s:String):Array<Array<CssTerm>> {
		var parts = [for (p in s.split("/")) line(p)];
		var rs = parts[0], cs = parts.length > 1 ? parts[1] : alone(rs);
		var re = parts.length > 2 ? parts[2] : alone(rs), ce = parts.length > 3 ? parts[3] : alone(cs);
		return [rs, cs, re, ce];
	}

	static function line(s:String):Array<CssTerm> {
		var t = new GridTerms(s).list(-1);
		return t.length == 0 ? [Keyword("auto")] : t;
	}

	// (a line left out: its start's name where that is one name alone, else auto)
	static function alone(start:Array<CssTerm>):Array<CssTerm>
		return start.length == 1 && start[0].match(Ident(_)) ? start : [Keyword("auto")];

	final s:String;
	var i = 0;

	function new(s:String)
		this.s = s ?? "";

	// (terms until the end, or until a closing character)
	function list(close:Int):Array<CssTerm> {
		var out = [];
		while (true) {
			while (i < s.length && s.fastCodeAt(i) == " ".code) i++;
			if (i >= s.length) break;
			var c = s.fastCodeAt(i);
			if (c == close) {
				i++;
				break;
			}
			if (c == ",".code || c == "/".code) {
				i++;
				out.push(Delim(String.fromCharCode(c)));
				continue;
			}
			if (c == "[".code) {
				i++;
				out.push(Brackets("[", list("]".code)));
				continue;
			}
			if (c == "\"".code || c == "'".code) {
				var end = s.indexOf(String.fromCharCode(c), i + 1);
				if (end < 0) end = s.length;
				out.push(Str(s.substring(i + 1, end)));
				i = end + 1;
				continue;
			}
			var start = i;
			while (i < s.length && " ,()[]/".indexOf(s.charAt(i)) < 0) i++;
			var w = s.substring(start, i);
			if (i < s.length && s.fastCodeAt(i) == "(".code) {
				i++;
				out.push(Func(w.toLowerCase(), list(")".code)));
				continue;
			}
			out.push(word(w));
		}
		return out;
	}

	static function word(w:String):CssTerm {
		var lower = w.toLowerCase();
		if (KEYWORDS.indexOf(lower) >= 0) return Keyword(lower);
		// (a number, then its unit: no regular expression linked for it)
		var k = 0, digits = 0;
		if (k < w.length && (w.charAt(k) == "+" || w.charAt(k) == "-")) k++;
		while (k < w.length && (w.fastCodeAt(k) >= "0".code && w.fastCodeAt(k) <= "9".code || w.charAt(k) == ".")) {
			if (w.charAt(k) != ".") digits++;
			k++;
		}
		if (digits == 0) return Ident(w);
		var number = w.substr(0, k), unit = w.substr(k).toLowerCase(), v = Std.parseFloat(number);
		return switch unit {
			case "": Number(v, number.indexOf(".") < 0);
			case "%": Percentage(v);
			case u: Dimension(v, u);
		}
	}
}
