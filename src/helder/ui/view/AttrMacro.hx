package helder.ui.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.TypeTools;

// StyleAttrs's apply, generated from Style: every public property with a
// setter is an attribute, named as the property (CSS's name in camel:
// helder.view.Vocabulary.STYLES, which it checks against Style), its value
// converted by the property's type (Null<T> as T):
// - a function of StyleAttrs named as the property, (style, v), when it has
//   one (the properties whose values CSS writes its own way: background,
//   radius, transform...);
// - Float, Int, Bool, String; Dim ("50%", 12), EdgesValue ("8 12"), Color
//   (CSS's colours, 0xRRGGBB opaque);
// - an enum abstract: its values' names in any case, kebab-case or not
//   ("space-between": SpaceBetween), or the names their @:css gives
//   ("flex-start", "ew-resize");
// - a type with a static parse(String) (Shadow, Gradient...): a string
//   parsed, else the value as it is;
// - else the value as it is.
// So a property added to Style is an attribute with no more code. Each
// property's conversion is a function of its own (the one above, or one made
// here), and so is setting it on a node, set<Property>(node, name, v): a
// literal attribute name in markup calls that alone (setter, NodeRenderer's
// setProperty macro), so a program links the parsers its attributes use.
class AttrMacro {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var own = [for (f in fields) f.name => true];
		var cases:Array<Case> = [];
		var names:Array<Expr> = [];
		var enums = new Map<String, Bool>();
		var pos = Context.currentPos();
		// (markup's words are Style's: the two tables one)
		var props = [for (f in styleProperties()) f.name], words = helder.view.Vocabulary.STYLES;
		var missing = [for (p in props) if (words.indexOf(p) < 0) p], extra = [for (w in words) if (props.indexOf(w) < 0) w];
		if (missing.length + extra.length > 0)
			Context.fatalError("helder.ui: Vocabulary.STYLES is not Style's properties (" + (missing.length > 0 ? "missing " + missing.join(", ") : "")
				+ (extra.length > 0 ? " not Style's " + extra.join(", ") : "") + ")", pos);
		for (f in styleProperties()) {
			var name = f.name;
			if (!own.exists(name)) {
				var conv = convert(f.type, fields, enums);
				fields.push({
					name: name,
					access: [AStatic],
					pos: pos,
					// (converted as its type is: a literal of an enum's checked, checkValue)
					meta: [{name: ":converted", pos: pos}],
					kind: FFun({args: [{name: "style", type: macro :helder.ui.Style}, {name: "v", type: macro :Dynamic}], ret: macro :Void, expr: macro style.$name = $conv})
				});
			}
			fields.push({
				name: setterName(name),
				access: [APublic, AStatic],
				pos: pos,
				kind: FFun({
					args: [{name: "n", type: macro :helder.ui.Node}, {name: "name", type: macro :String}, {name: "v", type: macro :Dynamic}],
					ret: macro :Void,
					expr: macro $i{name}(n.style, v)
				})
			});
			cases.push({values: [macro $v{name}], expr: macro $i{name}(style, v)});
			names.push(macro $v{name} => true);
		}
		var sw = {expr: ESwitch(macro name, cases, macro return false), pos: Context.currentPos()};
		fields.push({
			name: "apply",
			access: [APublic, AStatic],
			pos: Context.currentPos(),
			kind: FFun({args: [{name: "style", type: macro :helder.ui.Style}, {name: "name", type: macro :String}, {name: "v", type: macro :Dynamic}],
				ret: macro :Bool, expr: macro {
					$sw;
					return true;
				}})
		});
		fields.push({
			name: "NAMES",
			access: [AStatic, AFinal],
			pos: Context.currentPos(),
			kind: FVar(macro :Map<String, Bool>, macro [$a{names}])
		});
		return fields;
	}

	// Style's properties that are attributes: the public ones with a setter
	static function styleProperties():Array<ClassField> {
		var style = switch Context.getType("helder.ui.Style") {
			case TInst(c, _): c.get();
			case _: throw "helder.ui.Style";
		}
		return [for (f in style.fields.get()) if (f.isPublic && f.kind.match(FVar(_, AccCall))) f];
	}

	static function setterName(property:String):String
		return "set" + property.charAt(0).toUpperCase() + property.substr(1);

	// (an @:attribute function's attribute: as @:attribute("aria-label") names it, else as the function)
	static function attributeName(meta:Null<Array<MetadataEntry>>, field:String):String {
		for (m in meta ?? [])
			if (m.name == ":attribute" && m.params != null && m.params.length == 1)
				switch m.params[0].expr {
					case EConst(CString(s, _)): return s;
					case _:
				}
		return field;
	}

	// NodeRenderer's setAttribute, made from its own attributes (its
	// @:attribute functions), data-* and aria-*, then Style's
	// (StyleAttrs.apply); React's names (htmlFor, className) as HTML's; any
	// other name thrown with the one meant (Vocabulary)
	public static function renderer():Array<Field> {
		var fields = Context.getBuildFields();
		var cases:Array<Case> = [];
		// (each by its class: an attribute may be named as setAttribute's arguments, name)
		var cls = Context.getLocalClass().get(), path = cls.pack.concat([cls.name]);
		for (f in fields)
			if (Lambda.exists(f.meta, m -> m.name == ":attribute"))
				cases.push({values: [macro $v{attributeName(f.meta, f.name)}], expr: macro $p{path.concat([f.name])}(n, name, v)});
		var sw = {expr: ESwitch(macro name, cases, macro if (!StyleAttrs.apply(n.style, name, v)) noAttribute(n, name)), pos: Context.currentPos()};
		fields.push({
			name: "setAttribute",
			access: [APublic, AStatic],
			pos: Context.currentPos(),
			kind: FFun({
				args: [{name: "n", type: macro :helder.ui.Node}, {name: "name", type: macro :String}, {name: "v", type: macro :Dynamic}],
				ret: macro :Void,
				expr: macro {
					name = helder.view.Vocabulary.canonical(name);
					if (StringTools.startsWith(name, "data-")) setData(n, name, v) else if (StringTools.startsWith(name, "aria-")) setAria(n, name, v) else $sw;
				}
			})
		});
		return fields;
	}

	// the function setting attribute name on a node, (node, name, v): one of
	// NodeRenderer's own, data-* and aria-*, then Style's, else setAttribute;
	// a lookup in the build's table (paths), the hint (Vocabulary) only for a
	// name it has not
	public static function setter(name:String, pos:Position, lenient = false):Expr {
		var path = paths().get(name);
		if (path == null) {
			name = helder.view.Vocabulary.canonical(name);
			if (StringTools.startsWith(name, "data-")) path = DATA;
			else if (StringTools.startsWith(name, "aria-")) path = ARIA;
			else path = paths().get(name);
		}
		if (path != null) return {expr: EMeta({name: ":privateAccess", params: [], pos: pos}, macro @:pos(pos) $p{path}), pos: pos};
		// (a name none of them has: an error at the attribute, the name meant
		// suggested (Vocabulary), as an unknown event is, MarkupMacro.handler;
		// lenient, an agnostic literal's element of another renderer's: looked
		// up at run time, which throws when it is set)
		if (!lenient) Context.error(unknown(name), pos);
		return macro @:pos(pos) helder.ui.view.NodeRenderer.setAttribute;
	}

	static final DATA = ["helder", "ui", "view", "NodeRenderer", "setData"];
	static final ARIA = ["helder", "ui", "view", "NodeRenderer", "setAria"];

	// (each attribute's function's path: the renderer's own, then Style's; made
	// once a build, the macro context's statics a build's)
	static var table_:Null<Map<String, Array<String>>> = null;
	static var order:Array<String> = [];
	// (the enum attributes, converted as their type is: their type's name and its values' keys)
	static var enums_:Map<String, {type:String, keys:Array<String>}> = [];

	static function paths():Map<String, Array<String>> {
		if (table_ != null) return table_;
		var t = new Map<String, Array<String>>();
		order = [];
		function add(name:String, path:Array<String>)
			if (!t.exists(name)) {
				t.set(name, path);
				order.push(name);
			}
		switch Context.getType("helder.ui.view.NodeRenderer") {
			case TInst(c, _):
				for (f in c.get().statics.get())
					if (f.meta.has(":attribute")) add(attributeName(f.meta.get(), f.name), ["helder", "ui", "view", "NodeRenderer", f.name]);
			case _:
		}
		// (StyleAttrs' own converters: a property converted its own way has no keys checked)
		var own = switch Context.getType("helder.ui.view.StyleAttrs") {
			case TInst(c, _): [for (f in c.get().statics.get()) if (!f.meta.has(":converted")) f.name => true];
			case _: new Map<String, Bool>();
		}
		enums_ = [];
		for (f in styleProperties()) {
			add(f.name, ["helder", "ui", "view", "StyleAttrs", setterName(f.name)]);
			if (!own.exists(f.name)) {
				var e = enumKeys(f.type);
				if (e != null) enums_.set(f.name, e);
			}
		}
		return table_ = t;
	}

	// the message for an attribute none of ui's elements has: the name meant (Vocabulary)
	public static function unknown(name:String):String
		return helder.view.Vocabulary.attribute("view", name) ?? "markup: no attribute " + name;

	// a literal value of an attribute checked: one an enum attribute does not take an error, its values said
	public static function checkValue(name:String, value:String, pos:Position) {
		paths();
		var e = enums_.get(name);
		if (e != null && e.keys.indexOf(AttrNames.key(value)) < 0) Context.error(AttrNames.badValue(name, value, e.type, e.keys), pos);
	}

	// an enum abstract's keys (its values' names and strings, @:css's, as AttrNames.key gives them), null: not one
	static function enumKeys(t:Type):Null<{type:String, keys:Array<String>}> {
		t = lazy(t);
		switch t {
			case TAbstract(_.get() => {name: "Null", pack: []}, [inner]) | TType(_.get() => {name: "Null", pack: []}, [inner]): return enumKeys(inner);
			case TType(_, _): return enumKeys(Context.follow(t, true));
			case TAbstract(a, _) if (a.get().meta.has(":enum")):
				var keys = [];
				for (f in a.get().impl.get().statics.get()) {
					if (!f.meta.has(":enum") || !f.kind.match(FVar(_, _))) continue;
					if (keys.indexOf(AttrNames.key(f.name)) < 0) keys.push(AttrNames.key(f.name));
					switch f.expr()?.expr {
						case TConst(TString(s)) | TCast({expr: TConst(TString(s))}, _) if (keys.indexOf(AttrNames.key(s)) < 0): keys.push(AttrNames.key(s));
						case _:
					}
					for (m in f.meta.extract(":css"))
						for (p in m.params)
							switch p.expr {
								case EConst(CString(s, _)) if (keys.indexOf(AttrNames.key(s)) < 0): keys.push(AttrNames.key(s));
								case _:
							}
				}
				return {type: a.get().name, keys: keys};
			case _:
				return null;
		}
	}

	// what setter resolves at compile time, as names to their functions' paths
	// (data-* and aria-* as prefixes, * any other name: setAttribute):
	// helder.typescript's manifest lists them (NodeRenderer.setterTable)
	// (an enum attribute's row: its type's name and the keys of its values, which a literal is checked by)
	public static function table():Array<{name:String, fn:String, ?type:String, ?keys:Array<String>}> {
		var t = paths();
		var out:Array<{name:String, fn:String, ?type:String, ?keys:Array<String>}> = [{name: "data-*", fn: DATA.join(".")}, {name: "aria-*", fn: ARIA.join(".")}];
		for (n in order) {
			var e = enums_.get(n);
			out.push(e == null ? {name: n, fn: t[n].join(".")} : {name: n, fn: t[n].join("."), type: e.type, keys: e.keys});
		}
		out.push({name: "*", fn: "helder.ui.view.NodeRenderer.setAttribute"});
		return out;
	}

	// v as the type t
	static function convert(t:Type, fields:Array<Field>, enums:Map<String, Bool>):Expr {
		var nullable = false;
		switch lazy(t) {
			case TAbstract(_.get() => {name: "Null", pack: []}, [inner]):
				t = lazy(inner);
				nullable = true;
			case TType(_.get() => {name: "Null", pack: []}, [inner]):
				t = lazy(inner);
				nullable = true;
			case l = TType(_, _):
				// (a typedef: its type; ui's Cursor is helder.os's)
				t = lazy(Context.follow(l, true));
			case l:
				t = l;
		}
		var e = switch t {
			case TAbstract(_.get() => {name: "Float", pack: []}, _): macro float(v);
			case TAbstract(_.get() => {name: "Int", pack: []}, _): macro Std.int(float(v));
			case TAbstract(_.get() => {name: "Bool", pack: []}, _): return macro v == true || v == "true";
			case TInst(_.get() => {name: "String", pack: []}, _): return macro v == null ? null : Std.string(v);
			case TAbstract(_.get() => {name: "Dim"}, _): macro dim(v);
			case TAbstract(_.get() => {name: "EdgesValue"}, _): macro edges(v);
			case TAbstract(_.get() => {name: "Color"}, _): macro colorOf(v);
			case TAbstract(a, _) if (a.get().meta.has(":enum")):
				var fn = "enum" + a.get().name;
				if (!enums.exists(fn)) {
					enums.set(fn, true);
					fields.push(enumParser(fn, a.get(), t));
				}
				return macro $i{fn}(v);
			case _:
				var ct = t.toComplexType();
				if (hasParse(t)) {
					var path = typeExpr(t);
					macro Std.isOfType(v, String) ? $path.parse(v) : (v : $ct);
				} else return macro(v : $ct);
		}
		return nullable ? macro v == null ? null : $e : e;
	}

	// t, typed if it is not yet (a field's type read before its class is typed)
	static function lazy(t:Type):Type {
		while (true)
			switch t {
				case TLazy(f): t = f();
				case _: return t;
			}
	}

	static function hasParse(t:Type):Bool
		return switch t {
			case TInst(c, _): c.get().statics.get().filter(f -> f.name == "parse").length > 0;
			case TAbstract(a, _): a.get().impl != null && a.get().impl.get().statics.get().filter(f -> f.name == "parse").length > 0;
			case _: false;
		}

	// the type's path as an expression (its module's, when it is not the module's main type)
	static function typeExpr(t:Type):Expr {
		var b:BaseType = switch t {
			case TInst(c, _): c.get();
			case TAbstract(a, _): a.get();
			case TEnum(e, _): e.get();
			case _: throw "a type";
		}
		var mod = b.module.split(".").pop();
		var path = b.pack.copy();
		if (mod != b.name) path.push(mod);
		path.push(b.name);
		return macro $p{path};
	}

	// an enum abstract's values by name (key: lower case, no - or _) and @:css
	static function enumParser(fn:String, a:AbstractType, t:Type):Field {
		var cases:Array<Case> = [];
		var path = typeExpr(t);
		var ct = t.toComplexType();
		for (f in a.impl.get().statics.get()) {
			if (!f.meta.has(":enum") || !f.kind.match(FVar(_, _))) continue;
			var keys = [key(f.name)];
			// (a string enum's value too: "ew-resize")
			switch f.expr()?.expr {
				case TConst(TString(s)) | TCast({expr: TConst(TString(s))}, _) if (keys.indexOf(key(s)) < 0): keys.push(key(s));
				case _:
			}
			for (m in f.meta.extract(":css"))
				for (p in m.params)
					switch p.expr {
						case EConst(CString(s, _)): keys.push(key(s));
						case _:
					}
			var name = f.name;
			cases.push({values: [for (k in keys) macro $v{k}], expr: macro $path.$name});
		}
		var msg = " is not a " + a.name;
		var sw = {expr: ESwitch(macro key(v), cases, macro throw "helder.ui: " + v + $v{msg}), pos: Context.currentPos()};
		return {
			name: fn,
			access: [AStatic],
			pos: Context.currentPos(),
			kind: FFun({args: [{name: "v", type: macro :Dynamic}], ret: macro :Null<$ct>, expr: macro {
				if (v == null) return null;
				if (!Std.isOfType(v, String)) return v;
				return $sw;
			}})
		};
	}

	static inline function key(s:String):String
		return AttrNames.key(s);

	// [every value of an enum abstract]
	public static function values(e:Expr):Expr {
		var t = Context.getType(haxe.macro.ExprTools.toString(e));
		var abs = switch t {
			case TAbstract(a, _): a.get();
			case _: Context.error("an enum abstract", e.pos);
		}
		var path = typeExpr(t);
		var items = [for (f in abs.impl.get().statics.get()) if (f.meta.has(":enum") && f.kind.match(FVar(_, _))) {
			var n = f.name;
			macro $path.$n;
		}];
		return macro $a{items};
	}
}
#end
