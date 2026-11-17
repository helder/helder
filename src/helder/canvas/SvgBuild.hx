package helder.canvas;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.canvas.Svg;

using haxe.macro.ExprTools;

// Svg.parse of a constant (a string, inline constants and literals joined
// by +) at compile time: Svg.read runs in the macro context and its result
// becomes the expressions that make it again (the groups, shapes, styles,
// gradients and matrices), so the program links no parser; anything else
// is read when the program runs.
class SvgBuild {
	public static function parse(text:Expr):Expr {
		var s = constant(try Context.typeExpr(text) catch (_:Dynamic) null);
		if (s == null) return macro helder.canvas.Svg.read($text);
		// (one static per drawing, made once: markup's <svg> re-rendered makes no new one)
		var name = "Drawing" + haxe.crypto.Md5.encode(s).substr(0, 12);
		var exists = try Context.getType("helder.canvas.drawings." + name) != null catch (_:Dynamic) false;
		if (!exists) {
			var svg = try Svg.read(s) catch (e:Dynamic) Context.error('Svg.parse: $e', text.pos);
			Context.defineType({
				pack: ["helder", "canvas", "drawings"],
				name: name,
				pos: text.pos,
				kind: TDClass(),
				fields: [{name: "svg", access: [APublic, AStatic, AFinal], kind: FVar(macro :helder.canvas.Svg, make(svg)), pos: text.pos}]
			});
		}
		return macro @:pos(text.pos) $p{["helder", "canvas", "drawings", name, "svg"]};
	}

	static function make(svg:Svg):Expr {
		return @:privateAccess macro @:privateAccess new helder.canvas.Svg(${float(svg.width)}, ${float(svg.height)},
			${svg.viewBox == null ? macro null : macro {x: ${float(svg.viewBox.x)}, y: ${float(svg.viewBox.y)}, w: ${float(svg.viewBox.w)}, h: ${float(svg.viewBox.h)}}},
			${nullFloat(svg.alignX)}, ${nullFloat(svg.alignY)}, $v{svg.slice}, ${group(svg.root)});
	}

	// (the string a typed expression always is, else null)
	static function constant(t:Null<TypedExpr>):Null<String> {
		if (t == null) return null;
		return switch t.expr {
			case TConst(TString(s)): s;
			case TParenthesis(e) | TCast(e, null): constant(e);
			case TBinop(OpAdd, a, b):
				var x = constant(a), y = constant(b);
				x != null && y != null ? x + y : null;
			case _: null;
		}
	}

	static function float(f:Float):Expr
		return {expr: EConst(CFloat(Std.string(f) + (Std.string(f).indexOf(".") < 0 && Std.string(f).indexOf("e") < 0 ? ".0" : ""))), pos: Context.currentPos()};

	static function nullFloat(f:Null<Float>):Expr
		return f == null ? macro null : float(f);

	static function floats(a:Array<Float>):Expr
		return {expr: EArrayDecl([for (f in a) float(f)]), pos: Context.currentPos()};

	static function ints(a:Array<Int>):Expr
		return {expr: EArrayDecl([for (i in a) macro $v{i}]), pos: Context.currentPos()};

	static function matrix(m:Matrix):Expr
		return macro new helder.canvas.Matrix(${float(m.a)}, ${float(m.b)}, ${float(m.c)}, ${float(m.d)}, ${float(m.e)}, ${float(m.f)});

	static function group(g:SvgGroup):Expr {
		var kids = [for (c in g.children) c is SvgGroup ? group(c) : shape(c)];
		var clip = g.clip == null ? macro null : {
			expr: EArrayDecl([for (c in g.clip) macro {path: ${floats(c.path)}, matrix: ${matrix(c.matrix)}, evenOdd: $v{c.evenOdd}}]),
			pos: Context.currentPos()
		};
		return macro helder.canvas.Svg.SvgGroup.of(${matrix(g.matrix)}, ${float(g.opacity)}, $a{kids}, $clip);
	}

	static function shape(s:SvgShape):Expr
		return macro new helder.canvas.Svg.SvgShape(${floats(s.path)}, ${matrix(s.matrix)}, ${style(s.style)}, ${float(s.opacity)});

	static function style(s:SvgStyle):Expr
		return macro helder.canvas.Svg.SvgStyle.of(${paint(s.fill)}, ${paint(s.stroke)}, ${float(s.fillOpacity)}, ${float(s.strokeOpacity)},
			${float(s.strokeWidth)}, $v{s.cap}, $v{s.join}, ${float(s.miterLimit)}, $v{s.evenOdd}, ${s.dashes == null ? macro null : floats(s.dashes)},
			${float(s.dashOffset)}, ${s.color == null ? macro null : macro $v{s.color}});

	static function paint(p:SvgPaint):Expr
		return switch p {
			case None: macro helder.canvas.Svg.SvgPaint.None;
			case Rgba(c): macro helder.canvas.Svg.SvgPaint.Rgba($v{c});
			case Current: macro helder.canvas.Svg.SvgPaint.Current;
			case Gradient(g): macro helder.canvas.Svg.SvgPaint.Gradient(helder.canvas.Svg.SvgGradient.of($v{g.linear}, ${floats([g.x1, g.y1, g.x2, g.y2, g.cx, g.cy, g.r, g.fx, g.fy])},
					$v{g.boundingBox}, ${matrix(g.matrix)}, $v{g.spread}, ${floats(g.offsets)}, ${ints(g.colors)}));
		}
}
#end
