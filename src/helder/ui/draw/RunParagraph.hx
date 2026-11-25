package helder.ui.draw;

import helder.text.FontFile;
import helder.ui.Paragraph;

// A paragraph as it was laid out, its glyphs placed, no text engine behind
// it: a frame read back (FrameReader), drawn by the Renderer's glyph path
// as the DrawParagraph it was made from (the same lines, the same glyph
// positions and faces, rasterized at the target's scale: crisp at any
// zoom). Each line: its top, baseline and width; each glyph drawn (spaces,
// line breaks and hidden ones left out): its face, id, x from the line's
// origin (its advance and offset), y offset, size (its run's), oblique, run.
class RunParagraph implements Paragraph {
	public var width(get, never):Float;
	public var height(get, never):Float;
	public var lineCount(get, never):Int;
	public var minWidth(get, never):Float;
	public var baseline(get, never):Float;

	// the paragraph's own size (a glyph of no run's)
	public final size:Float;
	public final lines:Array<RunLine>;
	public final faces:Array<FontFile> = [];
	public final ids:Array<Int> = [];
	public final xs:Array<Float> = [];
	public final dys:Array<Float> = [];
	public final sizes:Array<Float> = [];
	public final obliques:Array<Bool> = [];
	public final spans:Array<Int> = [];
	final w:Float;
	final h:Float;
	final min:Float;
	final base:Float;

	public function new(width:Float, height:Float, minWidth:Float, baseline:Float, size:Float, lines:Array<RunLine>) {
		w = width;
		h = height;
		min = minWidth;
		base = baseline;
		this.size = size;
		this.lines = lines;
	}

	inline function get_width()
		return w;

	inline function get_height()
		return h;

	inline function get_lineCount()
		return lines.length;

	inline function get_minWidth()
		return min;

	inline function get_baseline()
		return base;

	// (a still is not edited: no caret, hit or selection of its own)
	public function caret(i:Int):{x:Float, y:Float, height:Float}
		return {x: 0, y: 0, height: h};

	public function hit(x:Float, y:Float):Int
		return 0;

	public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}>
		return [];

	public function runs(width:Float, align:TextAlign):Array<GlyphRun> {
		var out:Array<GlyphRun> = [];
		var cur:Null<GlyphRun> = null;
		for (l in lines) {
			var lx = switch align {
				case Center: (width - l.width) / 2;
				case Right: width - l.width;
				case _: 0.0;
			}
			for (i in l.start...l.end) {
				var f = faces[i];
				if (cur == null || cur.font.id != f.id || cur.size != sizes[i] || cur.span != spans[i]) {
					cur = {
						font: {family: f.family, weight: f.weight, italic: f.italic, data: f.data, id: f.id},
						size: sizes[i],
						glyphs: [],
						x: [],
						y: [],
						text: [],
						span: spans[i]
					};
					out.push(cur);
				}
				cur.glyphs.push(ids[i]);
				cur.x.push(lx + xs[i]);
				cur.y.push(l.top + l.baseline + dys[i]);
				cur.text.push("");
			}
		}
		return out;
	}

	public function lineWidth(y:Float):Float {
		for (l in lines)
			if (y < l.top + l.height) return l.width;
		return lines.length == 0 ? 0 : lines[lines.length - 1].width;
	}

	public function decoration(start:Int, end:Int, kind:TextDecoration, scale:Float, ?thickness:Float, ?offset:Float):Array<{
		x:Float,
		y:Float,
		width:Float,
		height:Float,
		lineWidth:Float
	}>
		return [];
}

// a line: its top, baseline (below its top), width and height, its glyphs' range
typedef RunLine = {top:Float, baseline:Float, width:Float, height:Float, start:Int, end:Int};
