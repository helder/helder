package helder.ui.fast;

import helder.ui.fast.Style.Tint;

// A theme: its tokens' colours, light and dark each, and whether it is
// dark. A style's Theme.token resolves in the theme of the node's scope
// (Node.theme, else its parent's), part of what a style is resolved for,
// so that a theme changed restyles what reads its tokens.
//
//   final app = new Theme(["surface" => [0xFFFFFFFF, 0xFF18181B], "fg" => [0xFF18181B, 0xFFFAFAFA]]);
//   card = Style.of({background: Theme.token("surface"), color: Theme.token("fg")});
final class Theme {
	public final tokens:Map<String, Array<Int>>;
	public final dark:Bool;

	// the theme of no tokens (a token's colour transparent), light
	public static final base = new Theme([]);

	public function new(tokens:Map<String, Array<Int>>, dark = false) {
		this.tokens = tokens;
		this.dark = dark;
	}

	// The same tokens, dark or light (one theme each way: what styles resolved in it are cached by).
	public function tone(dark:Bool):Theme {
		if (dark == this.dark) return this;
		if (other == null) {
			other = new Theme(tokens, dark);
			other.other = this;
		}
		return other;
	}

	var other:Null<Theme> = null;

	// This theme with others over its tokens.
	public function with(more:Map<String, Array<Int>>):Theme {
		var t = tokens.copy();
		for (k => v in more) t.set(k, v);
		return new Theme(t, dark);
	}

	// A token of the theme a style resolves in.
	public static inline function token(name:String):Tint
		return Style.TintValue.Token(name);

	// a token's colour here (0: none)
	public function color(name:String):Int {
		var v = tokens.get(name);
		return v == null ? 0 : dark && v.length > 1 ? v[1] : v[0];
	}
}
