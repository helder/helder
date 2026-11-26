package studio;

// How sharp the canvas' frames are drawn, in pixels a story point: the
// canvas' own (its zoom times the display's) in halves, at least 1, at most
// MOST, no frame past SIDE pixels a side and the frames given PIXELS in all
// (a frame is one texture, no tiles: deeper, it is stretched)
class Sharp {
	public static inline var MOST = 4.0;
	public static inline var SIDE = 4096.0;
	public static inline var PIXELS = 16777216.0;

	public static function scale(px:Float, frames:Array<{w:Float, h:Float}>):Float {
		var most = MOST, area = 0.0;
		for (f in frames) {
			most = Math.min(most, SIDE / Math.max(1, Math.max(f.w, f.h)));
			area += f.w * f.h;
		}
		if (area > 0) most = Math.min(most, Math.sqrt(PIXELS / area));
		return Math.max(1, Math.min(Math.floor(most * 2) / 2, Math.ceil(px * 2 - 0.05) / 2));
	}
}
