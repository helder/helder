package helder.css;

using StringTools;

// Names hashed for the ancestor Bloom filter (CssBloom): FNV-1a over a
// String's units, ASCII-lowercased, so an id, class or tag hashes the same
// whatever its case (quirks mode's classes, HTML's tags: a filter that
// may say yes too often, never no wrongly). Never 0.
class CssHash {
	public static inline function of(s:String):Int
		return range(s, 0, s.length);

	public static function range(s:String, from:Int, to:Int):Int {
		var h = 0x811C9DC5;
		for (k in from...to) {
			var c = s.fastCodeAt(k);
			if (c >= "A".code && c <= "Z".code) c += 32;
			h = (h ^ c) * 0x01000193;
		}
		// (32 bits on every target, and not 0)
		h = h & 0x7FFFFFFF;
		return h == 0 ? 1 : h;
	}
}
