package helder.ui.fast;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// A theme: its tokens' values, light and dark, and which of the two it is.
// Loaded from a CSS file when the program is built (load): its :root's
// custom properties are its tokens, typed by their values, their dark ones
// under @media (prefers-color-scheme: dark) or light-dark(). A node's theme
// is its subtree's (Node.theme); a style's tokens resolve in the one in
// scope, and only styles that read tokens resolve again when it changes.
//
//   static final app = Theme.load("app.theme.css");  // :root { --surface: #fff; --pad: 8px }
//   final card = Style.of({background: app.surface, padding: app.pad});
//   tree.palette = app.tone(dark);
class Theme {
	public final dark:Bool;
	// (each token's value: a colour's ARGB, a length's px, a number; its dark one where it differs)
	final light:Map<String, Float>;
	final shade:Map<String, Float>;
	// (each token's kind, as its file has it: "colour", "length", "number")
	final kinds:Map<String, String>;
	// (one for each theme: what a style that reads tokens is resolved in)
	@:allow(helder.ui.fast) final id:Int;
	static var made = 0;

	// the theme of no tokens, light
	public static final base = new Theme(new Map(), new Map());

	@:noCompletion public function new(light:Map<String, Float>, shade:Map<String, Float>, dark = false, ?kinds:Map<String, String>) {
		this.light = light;
		this.shade = shade;
		this.dark = dark;
		this.kinds = kinds ?? new Map();
		id = made++;
	}

	// The same tokens, dark or light (one theme each way).
	public function tone(dark:Bool):Theme {
		if (dark == this.dark) return this;
		if (other == null) {
			other = new Theme(light, shade, dark, kinds);
			other.other = this;
		}
		return other;
	}

	var other:Null<Theme> = null;

	// This theme with another value for a token (light, and dark where it differs): a subtree's (Node.theme).
	public function with<T>(token:Token<T>, value:Float, ?darkValue:Float):Theme {
		var l = light.copy(), s = shade.copy();
		l.set(token.name, value);
		if (darkValue != null) s.set(token.name, darkValue) else s.remove(token.name);
		return new Theme(l, s, dark, kinds);
	}

	// a token's colour here (0: none)
	public function color(name:String):Int {
		var v = value(name);
		return v == null ? 0 : Std.int(v);
	}

	// a length or number token's value here (0: none)
	public function length(name:String):Float
		return value(name) ?? 0;

	// Its tokens' values here as CSS's component values (name without its "--": #3b82f6ff, 8px), what a document
	// in its scope has as custom properties (DocumentView.retheme).
	public function properties():Map<String, Array<helder.css.CssValue>> {
		var out = new Map<String, Array<helder.css.CssValue>>();
		for (k in light.keys()) {
			var v = value(k), i = Std.int(v), text = number(v);
			var kind:helder.css.CssToken.CssTokenKind = switch kinds.get(k) {
				case "colour":
					Hash(StringTools.hex(i >> 16 & 0xFF, 2) + StringTools.hex(i >> 8 & 0xFF, 2) + StringTools.hex(i & 0xFF, 2) + StringTools.hex(i >>> 24, 2), false);
				case "length": Dimension(v, i == v, text, "px");
				case _: Number(v, i == v, text);
			}
			out.set(k, [Token(new helder.css.CssToken(kind, 0, 0))]);
		}
		return out;
	}

	// (a number as CSS writes it: an integer's digits, else its decimals)
	static function number(v:Float):String {
		var i = Std.int(v);
		return i == v ? Std.string(i) : Std.string(v);
	}

	inline function value(name:String):Null<Float>
		return dark ? shade.get(name) ?? light.get(name) : light.get(name);

	// A theme of a CSS file's tokens (beside the calling file, else under a class path), its fields typed tokens.
	public static macro function load(path:ExprOf<String>):Expr {
		var p = switch path.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("Theme.load: a string literal", path.pos);
		}
		var file = locate(p, path.pos);
		var f = ThemeFile.of(file);
		var name = "Theme" + haxe.crypto.Md5.encode(file).substr(0, 12);
		var exists = try Context.getType("helder.ui.fast.themes." + name) != null catch (_:Dynamic) false;
		if (!exists) {
			var pos = Context.currentPos(), fields:Array<Field> = [], light:Array<Expr> = [], shade:Array<Expr> = [], kinds:Array<Expr> = [];
			for (k in f.order) {
				var t = f.tokens.get(k), field = camel(k, path.pos);
				var type = switch t.kind {
					case Color: macro :helder.gfx.Color;
					case Length: macro :helder.ui.fast.Token.Length;
					case Number: macro :helder.ui.fast.Token.Number;
				}
				fields.push({name: field, access: [APublic, AFinal], kind: FVar(macro :helder.ui.fast.Token<$type>, macro new helder.ui.fast.Token($v{k})), pos: pos});
				light.push(macro $v{k} => $v{t.light});
				kinds.push(macro $v{k} => $v{(t.kind : String)});
				if (t.dark != null) shade.push(macro $v{k} => $v{t.dark});
			}
			fields.push({
				name: "new",
				access: [APublic],
				kind: FFun({
					args: [],
					expr: macro super(${light.length == 0 ? macro new Map() : macro $a{light}}, ${shade.length == 0 ? macro new Map() : macro $a{shade}}, false,
						${kinds.length == 0 ? macro new Map() : macro $a{kinds}})
				}),
				pos: pos
			});
			Context.defineType({
				pack: ["helder", "ui", "fast", "themes"],
				name: name,
				pos: pos,
				kind: TDClass({pack: ["helder", "ui", "fast"], name: "Theme"}),
				fields: fields
			});
		}
		return macro new helder.ui.fast.themes.$name();
	}

	#if macro
	@:allow(helder.ui.fast) static function locate(p:String, pos:Position):String {
		var file = @:privateAccess helder.css.CssModule.locate(p, haxe.io.Path.directory(Context.getPosInfos(pos).file));
		if (file == null) Context.error('"$p": no such file beside the module or under a class path', pos);
		file = sys.FileSystem.fullPath(file);
		Context.registerModuleDependency(Context.getLocalModule(), file);
		return file;
	}

	// (--accent-soft: accentSoft)
	static function camel(name:String, pos:Position):String {
		var parts = name.split("-"), out = parts[0];
		for (q in parts.slice(1)) if (q.length > 0) out += q.charAt(0).toUpperCase() + q.substr(1);
		if (!~/^[a-z_][a-zA-Z0-9_]*$/.match(out)) Context.error('Theme.load: --$name is no Haxe field name', pos);
		return out;
	}
	#end
}
