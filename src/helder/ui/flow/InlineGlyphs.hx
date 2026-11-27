package helder.ui.flow;

import haxe.ds.Vector;
import helder.text.FontFile;
import helder.text.FontSet;

// The glyph runs of a layout's text fragments: what paint draws and a
// writer embeds, read by index (no object per glyph). A run is in one
// FontSet (its size, oblique), its glyphs runStart to runStart + runCount
// in visual order, each its face, glyph id, its origin's x from the run's
// (the fragment's left) and y offset from the baseline (y down), its
// advance, and the text unit its cluster starts at (copy and search).
// Kept by its layout and filled again by each layout, allocating only to grow.
class InlineGlyphs {
	public var runs(default, null) = 0;
	public var count(default, null) = 0;
	public final faces:Array<FontFile> = [];
	public final fontSets:Array<FontSet> = [];

	var rFont = new Vector<Int>(16);
	var rStart = new Vector<Int>(16);
	var rCount = new Vector<Int>(16);
	// (a run with a glyph in a face other than its set's first available font)
	var rFallback = new Vector<Bool>(16);
	var gFace = new Vector<Int>(256);
	var gId = new Vector<Int>(256);
	var gX = new Vector<Float>(256);
	var gY = new Vector<Float>(256);
	var gAdvance = new Vector<Float>(256);
	var gCluster = new Vector<Int>(256);

	public function new() {}

	// the FontSet of a run
	public inline function runFonts(r:Int):FontSet
		return fontSets[rFont[r]];

	public inline function runStart(r:Int):Int
		return rStart[r];

	public inline function runCount(r:Int):Int
		return rCount[r];

	// whether a run has glyphs in a fallback face (another than its set's first available font)
	public inline function runFallback(r:Int):Bool
		return rFallback[r];

	public inline function face(g:Int):FontFile
		return faces[gFace[g]];

	public inline function id(g:Int):Int
		return gId[g];

	public inline function x(g:Int):Float
		return gX[g];

	public inline function y(g:Int):Float
		return gY[g];

	public inline function advance(g:Int):Float
		return gAdvance[g];

	public inline function cluster(g:Int):Int
		return gCluster[g];

	public function clear() {
		runs = 0;
		count = 0;
		faces.resize(0);
		fontSets.resize(0);
		lastFace = null;
	}

	// a run begun in a FontSet: its glyphs are those added until the next
	public function begin(fonts:FontSet):Int {
		var k = fontSets.indexOf(fonts);
		if (k < 0) {
			k = fontSets.length;
			fontSets.push(fonts);
		}
		if (runs == rFont.length) {
			var n = runs * 2;
			rFont = ints(rFont, n);
			rStart = ints(rStart, n);
			rCount = ints(rCount, n);
			var b = new Vector<Bool>(n);
			Vector.blit(rFallback, 0, b, 0, runs);
			rFallback = b;
		}
		var r = runs++;
		rFont[r] = k;
		rStart[r] = count;
		rCount[r] = 0;
		rFallback[r] = false;
		runFirst = fonts.first;
		return r;
	}

	public function add(face:FontFile, id:Int, x:Float, y:Float, advance:Float, cluster:Int) {
		if (count == gId.length) {
			var n = count * 2;
			gFace = ints(gFace, n);
			gId = ints(gId, n);
			gCluster = ints(gCluster, n);
			gX = floats(gX, n);
			gY = floats(gY, n);
			gAdvance = floats(gAdvance, n);
		}
		var k = face == lastFace ? lastIndex : faces.indexOf(face);
		if (k < 0) {
			k = faces.length;
			faces.push(face);
		}
		lastFace = face;
		lastIndex = k;
		var g = count++;
		gFace[g] = k;
		gId[g] = id;
		gX[g] = x;
		gY[g] = y;
		gAdvance[g] = advance;
		gCluster[g] = cluster;
		rCount[runs - 1]++;
		if (face != runFirst) rFallback[runs - 1] = true;
	}

	var runFirst:Null<FontFile> = null;

	var lastFace:Null<FontFile> = null;
	var lastIndex = -1;

	// the runs from `runs` on let go (a line laid out again)
	public function truncate(runs:Int) {
		if (runs >= this.runs) return;
		count = rStart[runs];
		this.runs = runs;
	}

	// a glyph not drawn (an ellipsis' cut: id -1, as a hidden glyph's)
	public inline function hide(g:Int)
		gId[g] = -1;

	static function ints(v:Vector<Int>, n:Int):Vector<Int> {
		var w = new Vector<Int>(n);
		Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	static function floats(v:Vector<Float>, n:Int):Vector<Float> {
		var w = new Vector<Float>(n);
		Vector.blit(v, 0, w, 0, v.length);
		return w;
	}
}
