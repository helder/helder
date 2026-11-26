package helder.css;

import helder.css.CssTerm;

// 2D transform lists interpolated (Transforms 2 §10, §12): none as the
// other list's identity functions, the shorter list padded with the
// longer's; the functions both lists have at the same place, of the same
// primitive (translate, scale, rotate, skew), argument by argument; two
// matrices, and the rest of the lists from where they differ, as
// matrices decomposed (translation, scale, skew, a quaternion, as
// browsers decompose 2D ones too), interpolated and composed again. 3D
// functions and percentages in a matrix's part (the box's size) don't
// interpolate here.
class CssTransforms {
	public static function interpolate(a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		var none = (v:Array<CssTerm>) -> v.length == 1 && v[0].match(Keyword("none"));
		if (none(a) && none(b)) return a;
		var fa = none(a) ? [for (f in b) identity(f)] : [for (f in a) read(f)];
		var fb = none(b) ? [for (f in a) identity(f)] : [for (f in b) read(f)];
		if (fa.contains(null) || fb.contains(null)) return null;
		// (the shorter list padded with the longer's identities, Transforms 2 §10)
		for (k in fa.length...fb.length) fa.push(identity(b[k]));
		for (k in fb.length...fa.length) fb.push(identity(a[k]));
		if (fa.contains(null) || fb.contains(null)) return null;
		var out:Array<CssTerm> = [];
		var k = 0;
		while (k < fa.length && fa[k].primitive == fb[k].primitive) {
			var x = fa[k], y = fb[k];
			// (two matrices: as one, decomposed)
			if (x.primitive == "matrix") {
				var m = blended([x], [y], t);
				if (m == null) return null;
				out.push(m);
				k++;
				continue;
			}
			var args = [for (i in 0...x.args.length) CssInterpolate.term(x.args[i], y.args[i], t)];
			if (args.contains(null)) return null;
			// (the same function keeps its name and its arguments; two of a primitive are it)
			out.push(x.name == y.name ? Func(x.name, commas(trim(x.name, args, x.n > y.n ? x.n : y.n))) : Func(x.primitive, commas(args)));
			k++;
		}
		if (k < fa.length) {
			var m = blended(fa.slice(k), fb.slice(k), t);
			if (m == null) return null;
			out.push(m);
		}
		return out;
	}

	// (functions as one matrix each, decomposed, interpolated, composed again)
	static function blended(fa:Array<Fn>, fb:Array<Fn>, t:Float):Null<CssTerm> {
		var ma = matrix(fa), mb = matrix(fb);
		if (ma == null || mb == null) return null;
		var da = decompose(ma), db = decompose(mb);
		if (da == null || db == null) return null;
		var m = compose(blend(da, db, t));
		var flat = m[2] == 0 && m[3] == 0 && m[6] == 0 && m[7] == 0 && m[8] == 0 && m[9] == 0 && m[10] == 1 && m[11] == 0 && m[14] == 0;
		var values = flat ? [m[0], m[1], m[4], m[5], m[12], m[13]] : m;
		return Func(flat ? "matrix" : "matrix3d", commas([for (x in values) Number(x, false)]));
	}

	// (a function as its primitive and arguments in full: translatex(a) as translate(a, 0))
	static function read(f:CssTerm):Null<Fn> {
		var name, args;
		switch f {
			case Func(n, a):
				name = n;
				args = a.filter(x -> !x.match(Delim(",")));
			case _: return null;
		}
		inline function px(k:Int):CssTerm
			return k < args.length ? args[k] : Dimension(0, "px");
		inline function num(k:Int, d:Float):CssTerm
			return k < args.length ? args[k] : Number(d, false);
		inline function deg(k:Int):CssTerm
			return k < args.length ? args[k] : Dimension(0, "deg");
		var r:Null<Fn> = switch name {
			case "translate": {name: name, primitive: "translate", args: [px(0), px(1)], n: 0};
			case "translatex": {name: name, primitive: "translate", args: [px(0), Dimension(0, "px")], n: 0};
			case "translatey": {name: name, primitive: "translate", args: [Dimension(0, "px"), px(0)], n: 0};
			case "scale": {name: name, primitive: "scale", args: [num(0, 1), args.length > 1 ? args[1] : num(0, 1)], n: 0};
			case "scalex": {name: name, primitive: "scale", args: [num(0, 1), Number(1, false)], n: 0};
			case "scaley": {name: name, primitive: "scale", args: [Number(1, false), num(0, 1)], n: 0};
			case "rotate": {name: name, primitive: "rotate", args: [deg(0)], n: 0};
			case "skew": {name: name, primitive: "skew", args: [deg(0), deg(1)], n: 0};
			case "skewx": {name: name, primitive: "skew", args: [deg(0), Dimension(0, "deg")], n: 0};
			case "skewy": {name: name, primitive: "skew", args: [Dimension(0, "deg"), deg(0)], n: 0};
			case "matrix" if (args.length == 6): {name: name, primitive: "matrix", args: args, n: 0};
			case _: null;
		};
		if (r != null) r.n = args.length;
		return r;
	}

	// (a function's own arguments back: translatex's one)
	static function trim(name:String, args:Array<CssTerm>, n:Int):Array<CssTerm>
		return switch name {
			case "translate" | "skew" if (n == 1): [args[0]];
			case "translatex" | "scalex" | "skewx": [args[0]];
			case "translatey" | "scaley" | "skewy": [args[1]];
			case "rotate": [args[0]];
			case "scale" if (CssText.term(args[0]) == CssText.term(args[1])): [args[0]];
			case _: args;
		}

	static function identity(f:CssTerm):Null<Fn> {
		var r = read(f);
		if (r == null) return null;
		return switch r.primitive {
			case "translate": {name: r.name, primitive: r.primitive, args: [Dimension(0, "px"), Dimension(0, "px")], n: r.n};
			case "scale": {name: r.name, primitive: r.primitive, args: [Number(1, false), Number(1, false)], n: r.n};
			case "rotate": {name: r.name, primitive: r.primitive, args: [Dimension(0, "deg")], n: r.n};
			case "skew": {name: r.name, primitive: r.primitive, args: [Dimension(0, "deg"), Dimension(0, "deg")], n: r.n};
			case _: {name: "matrix", primitive: "matrix", args: [for (x in [1.0, 0, 0, 1, 0, 0]) Number(x, false)], n: r.n};
		}
	}

	static function commas(args:Array<CssTerm>):Array<CssTerm> {
		var out = [];
		for (k in 0...args.length) {
			if (k > 0) out.push(Delim(","));
			out.push(args[k]);
		}
		return out;
	}

	// ---- matrices: [a, b, c, d, e, f]

	static function matrix(fs:Array<Fn>):Null<Array<Float>> {
		var m = [1.0, 0, 0, 1, 0, 0];
		for (f in fs) {
			var n = [for (a in f.args) value(a)];
			if (n.contains(null)) return null;
			var g = switch f.primitive {
				case "translate": [1.0, 0, 0, 1, n[0], n[1]];
				case "scale": [n[0], 0, 0, n[1], 0, 0];
				case "rotate":
					var r = n[0] * Math.PI / 180;
					[Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0];
				case "skew": [1, Math.tan(n[1] * Math.PI / 180), Math.tan(n[0] * Math.PI / 180), 1, 0, 0];
				case _: n;
			}
			m = multiply(m, g);
		}
		return m;
	}

	// (px, deg or a number; a percentage, the box's, none)
	static function value(t:CssTerm):Null<Float>
		return switch t {
			case Number(v, _): v;
			case Dimension(v, "px" | "deg"): v;
			case _: null;
		}

	static function multiply(m:Array<Float>, n:Array<Float>):Array<Float>
		return [
			m[0] * n[0] + m[2] * n[1],
			m[1] * n[0] + m[3] * n[1],
			m[0] * n[2] + m[2] * n[3],
			m[1] * n[2] + m[3] * n[3],
			m[0] * n[4] + m[2] * n[5] + m[4],
			m[1] * n[4] + m[3] * n[5] + m[5]
		];

	// (Transforms 2 §12.2's decomposition, as browsers apply it to 2D
	// matrices too: the columns' translation, scale, skew and a quaternion;
	// null for a matrix that can't be inverted)
	static function decompose(m:Array<Float>):Null<Parts> {
		if (m[0] * m[3] - m[1] * m[2] == 0) return null;
		var cols = [[m[0], m[1], 0.0], [m[2], m[3], 0.0], [0.0, 0, 1]];
		var scale = [0.0, 0, 0], skew = [0.0, 0, 0];
		inline function dot(a:Array<Float>, b:Array<Float>):Float
			return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
		function combine(a:Array<Float>, b:Array<Float>, k:Float):Array<Float>
			return [a[0] - k * b[0], a[1] - k * b[1], a[2] - k * b[2]];
		function unit(a:Array<Float>, l:Float):Array<Float>
			return l == 0 ? a : [a[0] / l, a[1] / l, a[2] / l];
		scale[0] = Math.sqrt(dot(cols[0], cols[0]));
		cols[0] = unit(cols[0], scale[0]);
		skew[0] = dot(cols[0], cols[1]);
		cols[1] = combine(cols[1], cols[0], skew[0]);
		scale[1] = Math.sqrt(dot(cols[1], cols[1]));
		cols[1] = unit(cols[1], scale[1]);
		skew[0] /= scale[1];
		skew[1] = dot(cols[0], cols[2]);
		cols[2] = combine(cols[2], cols[0], skew[1]);
		skew[2] = dot(cols[1], cols[2]);
		cols[2] = combine(cols[2], cols[1], skew[2]);
		scale[2] = Math.sqrt(dot(cols[2], cols[2]));
		cols[2] = unit(cols[2], scale[2]);
		skew[1] /= scale[2];
		skew[2] /= scale[2];
		// (a reflection: every axis flipped, which leaves a rotation)
		var b = cols[1], c = cols[2];
		if (dot(cols[0], [b[1] * c[2] - b[2] * c[1], b[2] * c[0] - b[0] * c[2], b[0] * c[1] - b[1] * c[0]]) < 0)
			for (i in 0...3) {
				scale[i] = -scale[i];
				cols[i] = [-cols[i][0], -cols[i][1], -cols[i][2]];
			}
		var r = cols;
		var q = [
			0.5 * Math.sqrt(Math.max(1 + r[0][0] - r[1][1] - r[2][2], 0)),
			0.5 * Math.sqrt(Math.max(1 - r[0][0] + r[1][1] - r[2][2], 0)),
			0.5 * Math.sqrt(Math.max(1 - r[0][0] - r[1][1] + r[2][2], 0)),
			0.5 * Math.sqrt(Math.max(1 + r[0][0] + r[1][1] + r[2][2], 0))
		];
		if (r[2][1] > r[1][2]) q[0] = -q[0];
		if (r[0][2] > r[2][0]) q[1] = -q[1];
		if (r[1][0] > r[0][1]) q[2] = -q[2];
		return {translate: [m[4], m[5], 0], scale: scale, skew: skew, quaternion: q};
	}

	// (the parts interpolated, the quaternions slerped, Transforms 2 §12.3)
	static function blend(a:Parts, b:Parts, t:Float):Parts {
		inline function l(x:Array<Float>, y:Array<Float>):Array<Float>
			return [for (i in 0...x.length) x[i] + (y[i] - x[i]) * t];
		var qa = a.quaternion, qb = b.quaternion;
		var product = Math.min(Math.max(qa[0] * qb[0] + qa[1] * qb[1] + qa[2] * qb[2] + qa[3] * qb[3], -1), 1);
		var q = qa;
		if (Math.abs(product) < 1) {
			var theta = Math.acos(product), w = Math.sin(t * theta) / Math.sqrt(1 - product * product);
			var k = Math.cos(t * theta) - product * w;
			q = [for (i in 0...4) qa[i] * k + qb[i] * w];
		}
		return {translate: l(a.translate, b.translate), scale: l(a.scale, b.scale), skew: l(a.skew, b.skew), quaternion: q};
	}

	// (the parts composed again, a 4x4 by columns: translated, rotated,
	// skewed, scaled)
	static function compose(p:Parts):Array<Float> {
		var x = p.quaternion[0], y = p.quaternion[1], z = p.quaternion[2], w = p.quaternion[3];
		var m = [
			1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
			2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
			2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
			p.translate[0], p.translate[1], p.translate[2], 1
		];
		// (m times a unit matrix with k at a column's row: that column plus k of the row's column)
		inline function shear(col:Int, row:Int, k:Float)
			if (k != 0) for (i in 0...4) m[col * 4 + i] += k * m[row * 4 + i];
		shear(2, 1, p.skew[2]);
		shear(2, 0, p.skew[1]);
		shear(1, 0, p.skew[0]);
		for (c in 0...3) for (i in 0...4) m[c * 4 + i] *= p.scale[c];
		return m;
	}
}

private typedef Fn = {name:String, primitive:String, args:Array<CssTerm>, n:Int}
private typedef Parts = {translate:Array<Float>, scale:Array<Float>, skew:Array<Float>, quaternion:Array<Float>}
