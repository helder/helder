package helder.ui.draw;

import haxe.io.Bytes;
import helder.canvas.Matrix;
import helder.canvas.Svg;
import helder.ui.draw.FrameStreams.FrameInput;

// An SVG drawing (Svg: the shapes it was parsed to) as data and back, for
// a frame's icons (FrameArchive): rendered again at the size it was, the
// same pixels; at another, as crisp as the live one.
@:access(helder.canvas.Svg)
class SvgData {
	public static function write(svg:Svg):Bytes {
		var o = new FrameStreams();
		o.float(0, svg.width);
		o.float(1, svg.height);
		o.bool(svg.viewBox != null);
		if (svg.viewBox != null) {
			o.float(2, svg.viewBox.x);
			o.float(3, svg.viewBox.y);
			o.float(4, svg.viewBox.w);
			o.float(5, svg.viewBox.h);
		}
		o.bool(svg.alignX != null);
		if (svg.alignX != null) {
			o.float(6, svg.alignX);
			o.float(7, svg.alignY ?? 0.5);
		}
		o.bool(svg.slice);
		group(o, svg.root);
		return o.bytes();
	}

	public static function read(b:Bytes):Svg {
		var r = new FrameInput(b);
		var w = r.float(0), h = r.float(1);
		var vb = r.bool() ? {x: r.float(2), y: r.float(3), w: r.float(4), h: r.float(5)} : null;
		var ax:Null<Float> = null, ay:Null<Float> = null;
		if (r.bool()) {
			ax = r.float(6);
			ay = r.float(7);
		}
		var slice = r.bool();
		return new Svg(w, h, vb, ax, ay, slice, readGroup(r));
	}

	static function group(o:FrameStreams, g:SvgGroup) {
		matrix(o, g.matrix);
		o.float(16, g.opacity);
		o.uint(g.clip == null ? 0 : g.clip.length + 1);
		if (g.clip != null)
			for (c in g.clip) {
				numbers(o, c.path);
				matrix(o, c.matrix);
				o.bool(c.evenOdd);
			}
		o.uint(g.children.length);
		for (c in g.children) {
			if (Std.isOfType(c, SvgGroup)) {
				o.bool(true);
				group(o, c);
				continue;
			}
			var s:SvgShape = c;
			o.bool(false);
			numbers(o, s.path);
			matrix(o, s.matrix);
			o.float(16, s.opacity);
			style(o, s.style);
		}
	}

	static function readGroup(r:FrameInput):SvgGroup {
		var m = readMatrix(r), opacity = r.float(16), n = Std.int(r.uint());
		var clip = n == 0 ? null : [
			for (_ in 1...n) {
				var path = readNumbers(r), cm = readMatrix(r);
				{path: path, matrix: cm, evenOdd: r.bool()};
			}
		];
		var g = new SvgGroup(m, opacity);
		g.clip = clip;
		for (_ in 0...Std.int(r.uint())) {
			if (r.bool()) {
				g.children.push(readGroup(r));
				continue;
			}
			var path = readNumbers(r), sm = readMatrix(r), so = r.float(16);
			g.children.push(new SvgShape(path, sm, readStyle(r), so));
		}
		return g;
	}

	static function style(o:FrameStreams, s:SvgStyle) {
		paint(o, s.fill);
		paint(o, s.stroke);
		o.float(17, s.fillOpacity);
		o.float(18, s.strokeOpacity);
		o.float(19, s.strokeWidth);
		o.uint(s.cap);
		o.uint(s.join);
		o.float(20, s.miterLimit);
		o.bool(s.evenOdd);
		o.uint(s.dashes == null ? 0 : s.dashes.length + 1);
		if (s.dashes != null)
			for (d in s.dashes)
				o.float(21, d);
		o.float(22, s.dashOffset);
		o.bool(s.color != null);
		if (s.color != null) o.color(s.color);
	}

	static function readStyle(r:FrameInput):SvgStyle {
		var fill = readPaint(r), stroke = readPaint(r);
		var fo = r.float(17), so = r.float(18), sw = r.float(19), cap = Std.int(r.uint()), join = Std.int(r.uint()), miter = r.float(20);
		var evenOdd = r.bool(), n = Std.int(r.uint());
		var dashes = n == 0 ? null : [for (_ in 1...n) r.float(21)];
		var offset = r.float(22);
		var color:Null<helder.gfx.Color> = r.bool() ? r.color() : null;
		return SvgStyle.of(fill, stroke, fo, so, sw, cap, join, miter, evenOdd, dashes, offset, color);
	}

	static function paint(o:FrameStreams, p:SvgPaint) {
		switch p {
			case None:
				o.uint(0);
			case Rgba(c):
				o.uint(1);
				o.color(c);
			case Current:
				o.uint(2);
			case Gradient(g):
				o.uint(3);
				o.bool(g.linear);
				for (k => v in [g.x1, g.y1, g.x2, g.y2, g.cx, g.cy, g.r, g.fx, g.fy])
					o.float(30 + k, v);
				o.bool(g.boundingBox);
				matrix(o, g.matrix);
				o.uint(g.spread);
				numbers(o, g.offsets);
				o.uint(g.colors.length);
				for (c in g.colors)
					o.color(c);
		}
	}

	static function readPaint(r:FrameInput):SvgPaint {
		return switch Std.int(r.uint()) {
			case 1: Rgba(r.color());
			case 2: Current;
			case 3:
				var linear = r.bool(), n = [for (k in 0...9) r.float(30 + k)], box = r.bool(), m = readMatrix(r), spread = Std.int(r.uint());
				var offsets = readNumbers(r);
				var colors:Array<helder.gfx.Color> = [for (_ in 0...Std.int(r.uint())) r.color()];
				Gradient(SvgGradient.of(linear, n, box, m, spread, offsets, colors));
			case _: None;
		}
	}

	static function matrix(o:FrameStreams, m:Matrix) {
		for (k => v in [m.a, m.b, m.c, m.d, m.e, m.f])
			o.float(8 + k, v);
	}

	static function readMatrix(r:FrameInput):Matrix
		return new Matrix(r.float(8), r.float(9), r.float(10), r.float(11), r.float(12), r.float(13));

	// (a path's commands, its points' x and y in slots of their own)
	static function numbers(o:FrameStreams, a:Array<Float>) {
		o.uint(a.length);
		for (k => v in a)
			o.float(40 + (k & 7), v);
	}

	static function readNumbers(r:FrameInput):Array<Float>
		return [for (k in 0...Std.int(r.uint())) r.float(40 + (k & 7))];
}
