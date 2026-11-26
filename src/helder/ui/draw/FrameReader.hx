package helder.ui.draw;

import helder.os.Edges;
import helder.gfx.Color;
import helder.image.Image;
import helder.text.FontFile;
import helder.ui.*;
import helder.ui.Paint.PaintValue;
import helder.ui.draw.FrameStreams.FrameInput;
import helder.ui.draw.FrameWriter.FrameOp;
import helder.ui.draw.RunParagraph.RunLine;

// A frame written by FrameWriter recorded into a DisplayList again, call by
// call, its fonts and images given (the archive's: FrameArchive.list), so
// that replaying the list draws what painting the frame drew.
class FrameReader {
	// passes: where what passes draw as data goes (PassData), each a GPU
	// texture of the list (PassData.MARK less its index) for the one who
	// replays it to draw; without, a placeholder's box
	public static function read(bytes:haxe.io.Bytes, fonts:Array<FontFile>, images:Array<Null<Image>>, ?passes:Array<PassData>):DisplayList {
		var list = new DisplayList(), r = new FrameInput(bytes);
		function box():{x:Float, y:Float, w:Float, h:Float}
			return {x: r.float(0), y: r.float(1), w: r.float(2), h: r.float(3)};
		function corners():Null<Corners>
			return r.bool() ? new Corners(r.float(60), r.float(61), r.float(62), r.float(63)) : null;
		function edges():Null<Edges>
			return r.bool() ? new Edges(r.float(64), r.float(65), r.float(66), r.float(67)) : null;
		function paint():Null<Paint>
			return switch Std.int(r.uint()) {
				case 1: PaintValue.Solid(r.color());
				case 2: PaintValue.Gradient(gradient(r));
				case _: null;
			}
		while (!r.done()) {
			switch r.op() {
				case FrameOp.TRANSLATE:
					list.translate(r.float(0), r.float(1));
				case FrameOp.PUSH_CLIP:
					var b = box(), radius = r.float(10);
					list.pushClip(b.x, b.y, b.w, b.h, radius, corners());
				case FrameOp.POP_CLIP:
					list.popClip();
				case FrameOp.PUSH_OPACITY:
					list.pushOpacity(r.float(11));
				case FrameOp.PUSH_GROUP:
					var a = r.float(11), b = box();
					list.pushGroup(a, b.x, b.y, b.w, b.h);
				case FrameOp.POP_OPACITY:
					list.popOpacity();
				case FrameOp.PUSH_TRANSFORM:
					var m = [for (k in 0...6) r.float(20 + k)];
					list.pushTransform(m[0], m[1], m[2], m[3], m[4], m[5]);
				case FrameOp.POP_TRANSFORM:
					list.popTransform();
				case FrameOp.RECT:
					var b = box(), radius = r.float(10), fill:Color = r.color(), bw = r.float(12), border:Color = r.color();
					var c = corners(), e = edges(), style:BorderStyle = cast Std.int(r.uint());
					list.rect(b.x, b.y, b.w, b.h, radius, fill, bw, border, c, e, style);
				case FrameOp.SHADOW:
					var b = box(), radius = r.float(10), color:Color = r.color(), blur = r.float(13), c = corners();
					var n = Std.int(r.uint()), offset = n == 0 ? null : [for (_ in 1...n) r.float(14)];
					list.shadow(b.x, b.y, b.w, b.h, radius, color, blur, c, offset);
				case FrameOp.INSET_SHADOW:
					var b = box(), radius = r.float(10), color:Color = r.color(), blur = r.float(13);
					var dx = r.float(15), dy = r.float(16), spread = r.float(17);
					list.insetShadow(b.x, b.y, b.w, b.h, radius, color, blur, dx, dy, spread, corners());
				case FrameOp.PATH:
					var p = new Path();
					p.evenOdd = r.bool();
					for (k in 0...Std.int(r.uint()))
						p.commands.push(r.float(30 + (k & 7)));
					var fill = paint(), stroke:Null<Stroke> = null;
					if (r.bool()) {
						var width = r.float(40), sp = paint(), cap = r.string(), join = r.string(), miter = r.float(41);
						var n = Std.int(r.uint()), dashes = n == 0 ? null : [for (_ in 1...n) r.float(42)], offset = r.float(43);
						stroke = {
							width: width,
							paint: sp ?? PaintValue.Solid(Color.BLACK),
							cap: cap == "" ? null : cast cap,
							join: join == "" ? null : cast join,
							miterLimit: miter < 0 ? null : miter,
							dashes: dashes,
							dashOffset: offset
						};
					}
					list.path(p, fill, stroke);
				case FrameOp.IMAGE:
					var k = Std.int(r.uint()), b = box();
					var u0 = r.float(50), v0 = r.float(51), u1 = r.float(52), v1 = r.float(53), radius = r.float(10), c = corners();
					var img = k == 0 ? null : images[k - 1];
					if (img != null) list.image(img, b.x, b.y, b.w, b.h, u0, v0, u1, v1, radius, c);
				case FrameOp.TEXT | FrameOp.TEXT_SHADOW:
					var shadow = r.ops.get(r.at - 1) == FrameOp.TEXT_SHADOW;
					var x = r.float(0), y = r.float(1), width = r.float(2), align:TextAlign = cast r.string(), color:Color = r.color();
					var n = Std.int(r.uint()), colors:Null<Array<Color>> = n == 0 ? null : [for (_ in 1...n) (r.color() : Color)];
					var p = paragraph(r, fonts);
					if (shadow) list.textShadow(p, x, y, width, align, color, r.float(13), colors) else list.text(p, x, y, width, align, color, colors);
				case FrameOp.PLACEHOLDER:
					var b = box();
					list.rect(b.x, b.y, b.w, b.h, 0, GpuPlaceholder.COLOR, 0, 0);
				case FrameOp.PASS_DATA:
					var b = box(), radius = r.float(10), c = corners(), d = PassData.read(r);
					if (passes == null) list.rect(b.x, b.y, b.w, b.h, radius, GpuPlaceholder.COLOR, 0, 0, c) else {
						passes.push(d);
						list.gpuTexture(cast 0, PassData.MARK - (passes.length - 1), b.x, b.y, b.w, b.h, radius, c);
					}
				case op:
					throw 'FrameReader: op $op unknown (a newer helder\'s frame)';
			}
		}
		return list;
	}

	@:access(helder.ui.Gradient)
	public static function gradient(r:FrameInput):Gradient {
		var linear = r.bool(), repeating = r.bool(), angle = r.float(70);
		var corner = r.bool() ? {x: r.int(), y: r.int()} : null;
		var circle = r.bool(), size = r.string(), sizeX = r.string(), sizeY = r.string(), atX = r.string(), atY = r.string();
		var colors:Array<Color> = [for (_ in 0...Std.int(r.uint())) (r.color() : Color)];
		var positions:Array<Null<String>> = [for (_ in colors) {var s = r.string(); s == "\x00" ? null : s;}];
		return new Gradient(linear, repeating, angle, corner, circle, size, sizeX == "\x00" ? null : sizeX, sizeY == "\x00" ? null : sizeY, atX, atY,
			colors, positions);
	}

	static function paragraph(r:FrameInput, fonts:Array<FontFile>):RunParagraph {
		var width = r.float(80), height = r.float(81), min = r.float(82), baseline = r.float(83), size = r.float(84);
		var lines:Array<RunLine> = [];
		var p = new RunParagraph(width, height, min, baseline, size, lines);
		for (_ in 0...Std.int(r.uint())) {
			var top = r.float(85), lb = r.float(86), lw = r.float(87), lh = r.float(88), n = Std.int(r.uint());
			var start = p.ids.length;
			for (_ in 0...n) {
				p.faces.push(fonts[Std.int(r.uint())]);
				p.ids.push(Std.int(r.uint()));
				p.xs.push(r.float(90));
				p.dys.push(r.float(91));
				p.sizes.push(r.float(92));
				p.obliques.push(r.bool());
				p.spans.push(r.int());
			}
			lines.push({top: top, baseline: lb, width: lw, height: lh, start: start, end: p.ids.length});
		}
		return p;
	}
}
