package helder.ui.fast;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.css.CssDeclaration;
import helder.css.CssRule;
import helder.css.CssValue;

using StringTools;

// A theme's file read when the program is built (Theme.load's,
// StyleModule's): its :root's custom properties, each a token typed by its
// value (a colour, px, a number), its dark value from @media
// (prefers-color-scheme: dark) { :root {...} } or light-dark(a, b). Read
// once a build, by its path.
class ThemeFile {
	public final path:String;
	public final tokens = new Map<String, ThemeToken>();
	public final order:Array<String> = [];
	final text:String;

	static final read = new Map<String, ThemeFile>();

	public static function of(path:String):ThemeFile {
		var f = read.get(path);
		if (f == null) read.set(path, f = new ThemeFile(path, sys.io.File.getContent(path)));
		return f;
	}

	function new(path:String, text:String) {
		this.path = path;
		this.text = text;
		for (r in new helder.css.Parser(text).sheet()) rule(r, false);
	}

	function rule(r:CssRule, dark:Bool)
		switch r {
			case Qualified(prelude, decls, nested):
				if (flat(prelude).trim() != ":root") fail(start(prelude), "a theme's rule is :root alone");
				if (nested.length > 0) fail(start(prelude), "a theme's :root has no nested rules");
				for (d in decls) declare(d, dark);
			case At("media", prelude, block) if (!dark && block != null):
				var q = flat(prelude);
				if (q.indexOf("prefers-color-scheme") < 0 || q.indexOf("dark") < 0) fail(start(prelude), "a theme's @media is (prefers-color-scheme: dark) alone");
				for (b in block) rule(b, true);
			case At(name, prelude, _): fail(start(prelude), 'a theme has no @$name');
			case Declarations(d): if (d.length > 0) fail(d[0].start, "a theme's declarations are in :root");
		}

	function declare(d:CssDeclaration, dark:Bool) {
		if (!d.name.startsWith("--")) fail(d.start, 'a theme declares custom properties (--name) alone, not ${d.name}');
		var name = d.name.substr(2), w = words(d.value);
		if (w.length != 1) fail(d.start, '--$name: one value');
		var v = value(w[0], d), t = tokens.get(name);
		if (dark) {
			if (t == null) fail(d.start, '--$name: dark, but not in :root');
			if (t.kind != v.kind) fail(d.start, '--$name: dark a ${v.kind}, light a ${t.kind}');
			t.dark = v.light;
			return;
		}
		if (t != null) fail(d.start, '--$name: declared twice');
		tokens.set(name, v);
		order.push(name);
	}

	function value(v:CssValue, d:CssDeclaration):ThemeToken
		return switch v {
			case Token({kind: Dimension(n, _, _, "px")}): new ThemeToken(Length, n, null);
			case Token({kind: Number(n, _, _)}): new ThemeToken(Number, n, null);
			case Function("light-dark", args, _, _):
				var parts = [for (a in words(args)) if (!a.match(Token({kind: Comma}))) a];
				if (parts.length != 2) fail(d.start, "light-dark(a, b): two colours");
				new ThemeToken(Color, colour(parts[0], d), colour(parts[1], d));
			case _: new ThemeToken(Color, colour(v, d), null);
		}

	function colour(v:CssValue, d:CssDeclaration):Float {
		var c = helder.css.CssColors.parse(v);
		if (c == null) fail(Parser.startOf(v), '${d.name}: a colour, px or a number');
		var s = helder.css.CssColors.srgb(c);
		inline function byte(x:Float):Int
			return Std.int(Math.max(0, Math.min(255, Math.round(x))));
		return byte(c.alpha * 255) << 24 | byte(s[0]) << 16 | byte(s[1]) << 8 | byte(s[2]);
	}

	static function words(values:Array<CssValue>):Array<CssValue>
		return [for (v in values) switch v {
			case Token({kind: Whitespace}): continue;
			case _: v;
		}];

	function flat(values:Array<CssValue>):String {
		if (values.length == 0) return "";
		var a = Parser.startOf(values[0]), last = values[values.length - 1];
		var b = switch last {
			case Token(t): t.end;
			case Function(_, _, _, close) | Block(_, _, close): close == null ? text.length : close.end;
		}
		return text.substring(a, b);
	}

	static function start(values:Array<CssValue>):Int
		return values.length == 0 ? 0 : Parser.startOf(values[0]);

	function fail<T>(at:Int, message:String):T {
		inline function bytes(k:Int)
			return haxe.io.Bytes.ofString(text.substr(0, k)).length;
		return Context.error('Theme: $message', Context.makePosition({file: path, min: bytes(at), max: bytes(at) + 1}));
	}
}

enum abstract ThemeKind(String) to String {
	var Color = "colour";
	var Length = "length";
	var Number = "number";
}

class ThemeToken {
	public final kind:ThemeKind;
	public final light:Float;
	public var dark:Null<Float>;

	public function new(kind:ThemeKind, light:Float, dark:Null<Float>) {
		this.kind = kind;
		this.light = light;
		this.dark = dark;
	}
}

private typedef Parser = helder.css.Parser;
#end
