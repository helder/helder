package helder.css;

import haxe.ds.ObjectMap;
import helder.css.CssCalc;
import helder.css.CssTerm;

// A document's interned values and groups: equal ones are one object, so
// groups compare their fields by identity and styles share groups.
class CssIntern {
	final lengths = new Map<String, CssLength>();
	final rgbas = new Map<String, CssRgba>();
	final displays = new Map<String, CssDisplay>();
	final lists = new Map<String, Array<CssTerm>>();
	final listIds = new ObjectMap<Array<CssTerm>, Int>();
	final groups:Array<Map<Int, Array<CssGroup>>> = [for (_ in 0...CssGroups.COUNT) new Map()];
	// (distinct groups, per group)
	public final counts:Array<Int> = [for (_ in 0...CssGroups.COUNT) 0];
	var values = 0;

	public function new() {}

	// (a lossless key: the terms' structure, numbers in full; not
	// Std.string, which elides what's nested deeply, as calc() in stretch())
	public static function key(t:Array<CssTerm>):String {
		var b = new StringBuf();
		write(b, t);
		return b.toString();
	}

	static function write(b:StringBuf, t:Array<CssTerm>) {
		b.add("[");
		for (x in t) {
			term(b, x);
			b.add(";");
		}
		b.add("]");
	}

	static function term(b:StringBuf, t:CssTerm)
		switch t {
			case Keyword(n): b.add('k$n');
			case Ident(n): b.add('i$n');
			case Number(v, integer): b.add('n$v${integer ? "i" : ""}');
			case Percentage(v): b.add('p$v');
			case Dimension(v, u): b.add('d$v$u');
			case Str(v): b.add('s${v.length}:$v');
			case Url(v, m): b.add('u${v.length}:$v${m.join(" ")}');
			case Color(c):
				b.add('c${c.space}${c.c.join(",")}/${c.alpha}${c.keyword ?? ""}');
				for (p in c.parts ?? []) {
					b.add('(${p.v} ${p.kind}');
					if (p.expr != null) node(b, p.expr);
					b.add(")");
				}
			case Calc(n, type, range):
				b.add('C$type${range == null ? "" : '${range.min},${range.max}${range.unit}'}');
				node(b, n);
			case Func(n, args):
				b.add('f$n');
				write(b, args);
			case Brackets(o, args):
				b.add('b$o');
				write(b, args);
			case Delim(v): b.add('D$v');
			case Raw(v): b.add('r${v.length}:$v');
			case Part(n, args):
				b.add('P$n');
				write(b, args);
		}

	static function node(b:StringBuf, n:CssCalcNode)
		switch n {
			case Value(v, u): b.add('($v$u)');
			case Sum(items) | Product(items) | Fn(_, items):
				b.add(switch n {
					case Sum(_): "(+";
					case Product(_): "(*";
					case Fn(name, _): '($name';
					case _: "(";
				});
				for (i in items) node(b, i);
				b.add(")");
			case Negate(i):
				b.add("(-");
				node(b, i);
				b.add(")");
			case Invert(i):
				b.add("(/");
				node(b, i);
				b.add(")");
			case Word(w): b.add('(w$w)');
		}

	public function length(t:Array<CssTerm>):Null<CssLength> {
		var k = key(t);
		var v = lengths.get(k);
		if (v != null) return v;
		v = CssLength.of(t);
		if (v == null) return null;
		v.id = values++;
		lengths.set(k, v);
		return v;
	}

	public function rgba(t:Array<CssTerm>):Null<CssRgba> {
		var k = key(t);
		var v = rgbas.get(k);
		if (v != null) return v;
		v = CssRgba.of(t);
		if (v == null) return null;
		v.id = values++;
		rgbas.set(k, v);
		return v;
	}

	// (blockified from original: a display of its own, so that groups and
	// styles with it are apart from those with the same display declared)
	public function display(t:Array<CssTerm>, ?original:Array<CssTerm>):CssDisplay {
		var k = original == null ? key(t) : key(t) + "<" + key(original);
		var v = displays.get(k);
		if (v != null) return v;
		v = CssDisplay.of(t);
		if (original != null) @:privateAccess v.original = display(original);
		v.id = values++;
		displays.set(k, v);
		return v;
	}

	public function terms(t:Array<CssTerm>):Array<CssTerm> {
		if (listIds.exists(t)) return t;
		var k = key(t);
		var v = lists.get(k);
		if (v != null) return v;
		lists.set(k, t);
		listIds.set(t, values++);
		return t;
	}

	public inline function id(t:Array<CssTerm>):Int
		return listIds.get(t) ?? -1;

	// The group interned: an equal one made before, or this one, now fixed.
	public function group(index:Int, g:CssGroup):CssGroup {
		if (g.id >= 0) return g;
		var h = @:privateAccess g.hash(this);
		var bucket = groups[index].get(h);
		if (bucket == null) groups[index].set(h, bucket = []);
		for (x in bucket) if (@:privateAccess x.same(g)) return x;
		g.id = values++;
		bucket.push(g);
		counts[index]++;
		return g;
	}
}
