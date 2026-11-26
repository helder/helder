package helder.canvas;

import helder.text.FontFile;

// Glyphs of one face at one size as a GlyphText painter takes them: each
// glyph's id, its pen in the painter's units (y down, on its baseline) and
// the characters of text it shows (UTF-16 units from start to end; a
// ligature's several, a cluster's glyphs after its first none of their own
// but the same range), in the order drawn (visual: right to left text
// reversed). A glyph is drawn as face.outline through
// [size / unitsPerEm * scaleX, 0, skew * size / unitsPerEm * scaleX, -size / unitsPerEm, x, y],
// skew 0.25 an oblique's.
class ShapedRun {
	public var face:FontFile;
	public var size = 0.0;
	public var scaleX = 1.0;
	public var skew = 0.0;
	public var text = "";
	public var count(default, null) = 0;
	public final ids:Array<Int> = [];
	public final xs:Array<Float> = [];
	public final ys:Array<Float> = [];
	public final starts:Array<Int> = [];
	public final ends:Array<Int> = [];

	public function new(face:FontFile, size:Float) {
		this.face = face;
		this.size = size;
	}

	public function clear()
		count = 0;

	public function push(id:Int, x:Float, y:Float, start:Int, end:Int) {
		ids[count] = id;
		xs[count] = x;
		ys[count] = y;
		starts[count] = start;
		ends[count] = end;
		count++;
	}

	// a copy of its own (a recording outlives the caller's buffers)
	public function copy():ShapedRun {
		var r = new ShapedRun(face, size);
		r.scaleX = scaleX;
		r.skew = skew;
		r.text = text;
		for (i in 0...count)
			r.push(ids[i], xs[i], ys[i], starts[i], ends[i]);
		return r;
	}
}
