package helder.css;

import helder.css.CssProperty;
import helder.css.CssTerm;

// A background layer (Backgrounds 3 §2.2): background-image's list says
// how many there are, the other lists repeat to as many.
typedef CssBackgroundLayer = {
	// null: none
	image:Null<CssTerm>,
	positionX:Array<CssTerm>,
	positionY:Array<CssTerm>,
	size:Array<CssTerm>,
	// x's and y's keywords
	repeat:Array<String>,
	attachment:String,
	origin:String,
	clip:String
}

enum CssContentItem {
	Text(text:String);
	Image(image:CssTerm);
	Counter(name:String, style:String);
	Counters(name:String, separator:String, style:String);
	Attribute(name:String);
	// open-quote, close-quote, no-open-quote, no-close-quote
	Quote(kind:String);
	// GCPM 3: string(name, which), a named string's value on the page
	// (which: first, start, last, first-except)
	StringValue(name:String, which:String);
	// element(name, which): a running element in a margin box
	RunningElement(name:String, which:String);
	// leader(): its fill (dotted ". ", solid "_", space " ", a string), repeated to the line's room
	Leader(fill:String);
	// content(text | before | after | first-letter | marker): string-set's
	ContentOf(part:String);
	// Content 3's cross-references, url: a string, url() or attr() term
	TargetCounter(url:CssTerm, name:String, style:String);
	TargetCounters(url:CssTerm, name:String, separator:String, style:String);
	TargetText(url:CssTerm, part:String);
	// anything else
	Other(term:CssTerm);
}

// string-set's: a name and its content list
typedef CssStringSet = {name:String, items:Array<CssContentItem>}

// (value: null for reversed() without one, its start worked out by CssCounters)
typedef CssCounter = {name:String, value:Null<Int>, reversed:Bool}

// Computed values that are lists, read as layout and paint want them.
class CssItems {
	public static function backgrounds(s:CssStyle):Array<CssBackgroundLayer> {
		var images = CssText.layers(s.terms(BackgroundImage));
		inline function list(p:CssProperty):Array<Array<CssTerm>>
			return CssText.layers(s.terms(p));
		var xs = list(BackgroundPositionX), ys = list(BackgroundPositionY), sizes = list(BackgroundSize), repeats = list(BackgroundRepeat),
			attachments = list(BackgroundAttachment), origins = list(BackgroundOrigin), clips = list(BackgroundClip);
		inline function at<T>(l:Array<T>, k:Int):T
			return l[k % l.length];
		return [for (k in 0...images.length) {
			image: images[k].length == 1 && images[k][0].match(Keyword("none")) ? null : images[k][0],
			positionX: at(xs, k),
			positionY: at(ys, k),
			size: at(sizes, k),
			repeat: repeat(at(repeats, k)),
			attachment: word(at(attachments, k)),
			origin: word(at(origins, k)),
			clip: word(at(clips, k))
		}];
	}

	// (repeat-x as repeat no-repeat, one keyword as both)
	static function repeat(t:Array<CssTerm>):Array<String> {
		var w = [for (x in t) word([x])];
		return switch w {
			case ["repeat-x"]: ["repeat", "no-repeat"];
			case ["repeat-y"]: ["no-repeat", "repeat"];
			case [a]: [a, a];
			case _: w;
		}
	}

	// null for normal and none.
	public static function content(t:Array<CssTerm>):Null<Array<CssContentItem>> {
		if (t.length == 1 && t[0].match(Keyword("normal" | "none"))) return null;
		var out = [];
		for (x in t) switch x {
			// (what follows is the alternative text)
			case Delim("/"): break;
			case Str(s): out.push(Text(s));
			case Url(_, _): out.push(Image(x));
			case Func("counter", args): out.push(Counter(name(args, 0), name(args, 1) ?? "decimal"));
			case Func("counters", args): out.push(Counters(name(args, 0), string(args, 1) ?? "", name(args, 2) ?? "decimal"));
			case Func("attr", args): out.push(Attribute(name(args, 0)));
			case Keyword(q = "open-quote" | "close-quote" | "no-open-quote" | "no-close-quote"): out.push(Quote(q));
			case Func("string", args): out.push(StringValue(name(args, 0), name(args, 1) ?? "first"));
			case Func("element", args) if (name(args, 0) != null): out.push(RunningElement(name(args, 0), name(args, 1) ?? "first"));
			case Func("leader", [Keyword(k)]): out.push(Leader(k == "dotted" ? ". " : k == "solid" ? "_" : " "));
			case Func("leader", [Str(s)]): out.push(Leader(s));
			case Func("content", args): out.push(ContentOf(name(args, 0) ?? "text"));
			case Func("target-counter", args) if (arg(args, 0) != null):
				out.push(TargetCounter(arg(args, 0), name(args, 1), name(args, 2) ?? "decimal"));
			case Func("target-counters", args) if (arg(args, 0) != null):
				out.push(TargetCounters(arg(args, 0), name(args, 1), string(args, 2) ?? "", name(args, 3) ?? "decimal"));
			case Func("target-text", args) if (arg(args, 0) != null): out.push(TargetText(arg(args, 0), name(args, 1) ?? "content"));
			case Func("image" | "image-set" | "linear-gradient" | "radial-gradient" | "conic-gradient" | "repeating-linear-gradient" | "repeating-radial-gradient"
				| "repeating-conic-gradient", _):
				out.push(Image(x));
			case _: out.push(Other(x));
		}
		return out;
	}

	// string-set's names and content lists; none, none.
	public static function strings(t:Array<CssTerm>):Array<CssStringSet> {
		if (t.length == 1 && t[0].match(Keyword("none"))) return [];
		return [
			for (l in CssText.layers(t)) if (l.length > 1) switch l[0] {
				case Ident(n): {name: n, items: content(l.slice(1)) ?? []};
				case _: continue;
			}
		];
	}

	// counter-reset's, counter-increment's or counter-set's counters.
	public static function counters(t:Array<CssTerm>):Array<CssCounter> {
		var out:Array<CssCounter> = [];
		for (x in t) switch x {
			case Ident(n): out.push({name: n, value: null, reversed: false});
			case Func("reversed", [Ident(n)]): out.push({name: n, value: null, reversed: true});
			case Number(v, _) if (out.length > 0): out[out.length - 1].value = Std.int(v);
			case _:
		}
		return out;
	}

	// font-family's families: names, and generics as their keywords.
	public static function families(t:Array<CssTerm>):Array<String>
		return [for (l in CssText.layers(t)) [for (x in l) switch x {
			case Str(s): s;
			case Ident(n) | Keyword(n): n;
			case _: CssText.term(x);
		}].join(" ")];

	static function word(t:Array<CssTerm>):String
		return t.length == 1 ? switch t[0] {
			case Keyword(k) | Ident(k): k;
			case x: CssText.term(x);
		} : CssText.join(t, CssText.term);

	// (a function's k-th argument past its commas: a name)
	// (symbols(): its text, for CssCounters to read)
	static function name(args:Array<CssTerm>, k:Int):Null<String> {
		var parts = CssText.layers(args);
		return k < parts.length && parts[k].length == 1 ? switch parts[k][0] {
			case Ident(n) | Keyword(n): n;
			case t = Func("symbols", _): CssText.term(t);
			case _: null;
		} : null;
	}

	// (a function's k-th argument past its commas, when it is one term)
	static function arg(args:Array<CssTerm>, k:Int):Null<CssTerm> {
		var parts = CssText.layers(args);
		return k < parts.length && parts[k].length == 1 ? parts[k][0] : null;
	}

	static function string(args:Array<CssTerm>, k:Int):Null<String> {
		var parts = CssText.layers(args);
		return k < parts.length && parts[k].length == 1 ? switch parts[k][0] {
			case Str(s): s;
			case _: null;
		} : null;
	}
}
