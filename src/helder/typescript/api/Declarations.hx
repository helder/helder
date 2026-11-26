package helder.typescript.api;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import helder.typescript.api.Modules;
import helder.typescript.api.dts.DefinitionEmitter;
import helder.typescript.api.dts.TypeEmitter;

// helder's TypeScript declaration files, generated from its Haxe types
// (typescript's README): each module's (Modules: helder/view, helder/ui,
// helder/web), beside its declaration class (src/helder/view/index.d.ts...).
// An init macro, run by helder's compiler (helder.typescript.Generator: its
// `--declarations` form, api/declarations.mjs, every TypeScript build):
//
//   write(["helder.view.TypeScript", ...])        // the files written
//   write([...], true)                            // checked: an error when one differs
//   write(["frames.FramesTypeScript"], true, [...])  // helder's modules (known) naming what they declare
//
// A file declares the module's classes (`declare class`, each the Haxe class
// `__haxe` names), its functions (`function f`, the static `__haxe` names), its
// interfaces and type aliases (abstracts: Signal, Read; enum abstracts:
// Load), and its part of JSX: helder/view's namespace (Element, a
// renderer's elements as any tag), the neutral elements' attributes and
// events where ui's module says so (jsx(neutral): MarkupMacro.NEUTRAL_EVENTS'
// handlers typed). What it names from another module is imported.
class Declarations {
	// (the math types TypeScript has as helder/math's classes: lower/Haxe.hx's MATH)
	static final MATH = [
		"helder.math.Vec2" => "Vec2",
		"helder.math.Vec3" => "Vec3",
		"helder.math.Vec4" => "Vec4",
		"helder.math.Mat4" => "Mat4",
		"helder.math.Quat" => "Quat"
	];

	// (known: modules typed, not written, so that what they declare is named
	// and imported as when they are written too: a few modules' files are
	// then the same as all of helder's)
	public static function write(decls:Array<String>, check = false, ?known:Array<String>)
		Context.onAfterInitMacros(() -> run(decls, check, known ?? []));

	static function run(decls:Array<String>, check:Bool, known:Array<String>) {
		var api = Modules.of(known.concat([for (d in decls) if (known.indexOf(d) < 0) d]));
		typedefs = new Map();
		// (the typedefs of the modules' packages their declarations name:
		// printed until no new one turns up; the known modules' too, so that
		// helder's module's are the same whichever are written, each found
		// there of a known module's package only)
		var helder = [for (m in api.modules) if (known.indexOf(m.decl) >= 0) m];
		var found = -1;
		while (found != Lambda.count(typedefs)) {
			found = Lambda.count(typedefs);
			for (m in api.modules) {
				owners = decls.indexOf(m.decl) >= 0 ? null : helder;
				module(api, m);
			}
			owners = null;
		}
		var stale = [];
		for (m in api.modules) {
			if (decls.indexOf(m.decl) < 0) continue;
			var text = module(api, m);
			var file = haxe.io.Path.join([m.dir, m.file]);
			var old = sys.FileSystem.exists(file) ? sys.io.File.getContent(file) : null;
			if (old == text) continue;
			if (check) stale.push(file) else {
				// (whole or not at all: builds write them at once, helder.typescript.Generator)
				var tmp = file + "." + Std.random(0x7fffffff) + ".tmp";
				sys.io.File.saveContent(tmp, text);
				sys.FileSystem.rename(tmp, file);
			}
		}
		if (stale.length > 0)
			Context.fatalError("helder.typescript: " + stale.join(", ") + " differ from helder's Haxe types: write them again (node src/helder/typescript/api/declarations.mjs)",
				Context.currentPos());
	}

	// (where each type is declared: its module and name)
	static function index(api:Api):Map<String, {module:ApiModule, name:String}> {
		var out = new Map();
		for (m in api.modules) {
			for (c in m.classes)
				if (c.only == null) out.set(key(c.cls), {module: m, name: c.cls.name});
			for (t in m.types) {
				var b = base(t);
				if (b != null) out.set(key(b), {module: m, name: b.name});
			}
		}
		return out;
	}

	// A typedef of a module's package (the longest of their packages its
	// own is or is under) that a declaration names: declared by that module
	// as `export type` and named where no other type of the module has its
	// name; one whose text differs taken and given (an @:typescript.input or
	// output in it: a ViewOf<R>, a props' children) is declared as taken,
	// named where it is (an argument: props) and written out where given.
	static var typedefs:Map<String, {module:ApiModule, name:String, type:DefType, named:Bool, takenOnly:Bool}> = new Map();

	// (the modules a typedef found may be of: null, any)
	static var owners:Null<Array<ApiModule>> = null;

	static function owner(api:Api, b:BaseType):Null<ApiModule> {
		var best:Null<ApiModule> = null, length = -1;
		var pack = b.pack.join(".");
		for (m in owners ?? api.modules) {
			var parts = m.decl.split(".");
			parts.pop();
			var p = parts.join(".");
			if ((pack == p || StringTools.startsWith(pack, p + ".")) && p.length > length) {
				best = m;
				length = p.length;
			}
		}
		return best;
	}

	static function typedefFound(api:Api, where:Map<String, {module:ApiModule, name:String}>, dt:DefType, declared:BaseType->Null<String>):Null<{module:ApiModule, name:String}> {
		var k = key(dt);
		var t = typedefs.get(k);
		if (t == null) {
			var m = owner(api, dt);
			if (m == null || dt.meta.has(":typescript.type")) return null;
			var taken = false;
			for (other in where) if (other.module == m && other.name == dt.name) taken = true;
			for (other in typedefs) if (other.module == m && other.name == dt.name) taken = true;
			typedefs.set(k, t = {module: m, name: dt.name, type: dt, named: false, takenOnly: false});
			if (!taken) {
				var writer:TypeWriter = {write: _ -> {}, declared: declared};
				var before = TypeEmitter.output;
				TypeEmitter.output = false;
				var input = TypeEmitter.toString(writer, dt.type);
				TypeEmitter.output = true;
				var output = TypeEmitter.toString(writer, dt.type);
				TypeEmitter.output = before;
				t.named = true;
				t.takenOnly = input != output;
			}
		}
		return t.named && !(t.takenOnly && TypeEmitter.output) ? {module: t.module, name: t.name} : null;
	}

	static function key(b:BaseType):String
		return b.module + ":" + b.name;

	static function base(t:Type):Null<BaseType>
		return switch t {
			case TInst(c, _): c.get();
			case TAbstract(a, _): a.get();
			case TType(d, _): d.get();
			case TEnum(e, _): e.get();
			case _: null;
		}

	static function module(api:Api, m:ApiModule):String {
		var where = index(api);
		var imports = new Map<String, Array<String>>();
		function declared(b:BaseType):Null<String> {
			// (helder.math's types: helder/math's
			// classes, the TypeScript program's, by value: lower/Haxe.hx's MATH)
			var math = MATH.get(b.pack.concat([b.name]).join("."));
			if (math != null) {
				var names = imports.get("helder/math");
				if (names == null) imports.set("helder/math", names = []);
				if (names.indexOf(math) < 0) names.push(math);
				return math;
			}
			// (helder.scene's Node, a handle: helder/scene's class, its id the
			// handle: lower/Haxe.hx's NODE)
			if (b.pack.concat([b.name]).join(".") == "helder.scene.Node") {
				var names = imports.get("helder/scene");
				if (names == null) imports.set("helder/scene", names = []);
				if (names.indexOf("Node") < 0) names.push("Node");
				return "Node";
			}
			var d = where.get(key(b));
			if (d == null) {
				var path = StringTools.endsWith(b.module, "." + b.name) || b.module == b.name ? b.module : b.module + "." + b.name;
				d = switch (try Context.getType(path) catch (_:Dynamic) null) {
					case TType(r, _) if (key(r.get()) == key(b)): typedefFound(api, where, r.get(), declared);
					case _: null;
				}
			}
			if (d == null) return null;
			if (d.module != m && !exported(d.module, d.name)) return null;
			if (d.module != m) {
				var specifier = d.module.name;
				// A library type reference can use the runtime declaration directly.
				// Going through its public .ts module would also load that module's code.
				if (StringTools.startsWith(m.name, "helder/")
					&& d.module.file == "runtime.d.ts") {
					var up = [for (_ in 1...m.name.split("/").length) ".."];
					var down = specifier.split("/").slice(1);
					specifier = up.concat(down).concat(["runtime"]).join("/");
				}
				var names = imports.get(specifier);
				if (names == null) imports.set(specifier, names = []);
				if (names.indexOf(d.name) < 0) names.push(d.name);
			}
			return d.name;
		}
		var e = new DefinitionEmitter(declared);
		var decl = switch Context.getType(m.decl) {
			case TInst(c, _): c.get();
			case _: throw "unreachable";
		}
		// (the declarations first: their imports are known after)
		var haxeNames = [for (c in m.opaque.concat(m.classes)) if (c.only == null)
			c.cls.name + ": " + haxe.Json.stringify(c.type)];
		for (f in m.functions)
			haxeNames.push(f.alias + ": " + haxe.Json.stringify(f.cls.type + "." + f.field));
		haxeNames.push("__module: " + haxe.Json.stringify(m.decl));
		e.line('declare const __haxe: {' + haxeNames.join(", ") + '};');
		for (t in m.types) {
			e.line();
			switch t {
				case TAbstract(a, _): e.emitAbstract(a.get().name, a.get());
				case TInst(c, _): e.emitOpaque(c.get().name, c.get());
				case TEnum(en, _): e.emitOpaque(en.get().name, en.get());
				case TType(d, _): e.emitTypedef(d.get().name, d.get());
				case _:
			}
		}
		var own = [for (t in typedefs) if (t.named && t.module == m) t];
		own.sort((a, b) -> Reflect.compare(a.name, b.name));
		for (t in own) {
			e.line();
			e.emitTypedef(t.name, t.type);
		}
		for (c in m.classes) {
			var open = exported(m, c.cls.name);
			if (c.only == null) {
				e.line();
				e.emitClass(c.cls.name, c.cls, open ? c.statics : [], c.members, c.ctor, open);
			}
			var fs = [for (f in m.functions) if (f.cls == c) f];
			if (fs.length > 0) e.line();
			for (f in fs)
				e.emitFunction(f.alias, [for (x in c.cls.statics.get()) if (x.name == f.field) x][0]);
		}
		for (j in m.jsx) {
			e.line();
			switch j {
				case "base": jsxBase(e, declared, e.from);
				case "neutral": jsxNeutral(e, declared, false);
				case "video": jsxNeutral(e, declared, true);
				case _: Context.error("helder.typescript: @:typescript.jsx is base, neutral or video", decl.pos);
			}
		}
		var head = [for (r in m.references) '/// <reference path="./$r" />'];
		head = head.concat([for (l in Docs.of(decl.meta.extract(":typescript")[0].pos)) "//" + (l == "" ? "" : " " + l)]);
		head.push("//");
		head.push("// Generated from helder's Haxe types (helder.typescript.api.Declarations: node");
		head.push("// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.");
		for (k in m.imports)
			head.push('import ' + haxe.Json.stringify(k) + ';');
		var names = [for (k in imports.keys()) k];
		names.sort(Reflect.compare);
		for (k in names) {
			var list = imports.get(k);
			list.sort(Reflect.compare);
			head.push('import type {' + list.join(", ") + '} from ' + haxe.Json.stringify(k) + ';');
		}
		return head.join("\n") + "\n\n" + e.toString() + "\nexport {};\n";
	}

	// (a class its module exports: not a function's host, not internal)
	static function exported(m:ApiModule, name:String):Bool
		return m.internal.indexOf(name) < 0
			&& !Lambda.exists(m.classes, c -> c.cls.name == name && c.only != null);

	// helder/view's JSX: TSX's values are Views, a component any function of
	// its props, a prop of a type made from other values (Read) taking them at
	// a TSX site (LibraryManagedAttributes: a constant, a signal, a function),
	// a renderer's elements any tag (checked when compiled)
	static function jsxBase(e:DefinitionEmitter, declared:BaseType->Null<String>, from:Array<String>) {
		var view = switch Context.getType("helder.view.View") {
			case TInst(c, _): declared(c.get());
			case _: null;
		}
		e.line('declare global {');
		e.line('\tnamespace JSX {');
		e.line('\t\ttype Element = ' + (view ?? "unknown") + ';');
		e.line('\t\t// components may return any content');
		e.line('\t\ttype ElementType = string | ((props: any) => unknown);');
		e.line('\t\tinterface ElementChildrenAttribute {');
		e.line('\t\t\tchildren: {};');
		e.line('\t\t}');
		if (from.length > 0) {
			e.line('\t\t// a component\'s props: ' + from.join(", ") + ' as what makes one');
			var t = "P[K]";
			for (f in from)
				t = 'NonNullable<P[K]> extends ' + f + '<infer T> ? ' + f + 'From<T> | Extract<P[K], undefined> : ' + t;
			e.line('\t\ttype LibraryManagedAttributes<C, P> = {[K in keyof P]: ' + t + '};');
		}
		e.line('\t\t// a renderer\'s elements: their attributes are the renderer\'s to check');
		e.line('\t\tinterface IntrinsicElements {');
		e.line('\t\t\t[tag: string]: {[attribute: string]: unknown};');
		e.line('\t\t}');
		e.line('\t}');
		e.line('}');
	}

	// the neutral elements (helder.view.Vocabulary's: view, text, button,
	// h2...): each element's attributes, the style properties typed as
	// StyleProps (CSS's names in camel), a value or a function of none that
	// reads it; its ref given its node, its handlers ui's events
	// (MarkupMacro.NEUTRAL_EVENTS) and its own; ARIA's and data-* any;
	// another name an error. video: helder.media's <video> alone
	static function jsxNeutral(e:DefinitionEmitter, declared:BaseType->Null<String>, video:Bool) {
		var writer:TypeWriter = {write: _ -> {}, declared: declared};
		function events(path:String):Map<String, String> {
			var out = new Map<String, String>();
			switch Context.follow(Context.getType(path)) {
				case TAnonymous(a):
					for (f in a.get().fields)
						out.set(f.name, TypeEmitter.toString(writer, f.type));
				case _:
			}
			return out;
		}
		var ui = video ? new Map<String, String>() : events(helder.view.MarkupMacro.NEUTRAL_EVENTS);
		function handlers(names:Array<String>, types:Map<String, String>)
			for (n in names)
				e.line('\t' + n + '?: ((event: ' + (types.get(n) ?? "unknown") + ') => void) | null;');
		// (helder/ui's types, by name in its own declarations, imported in another's)
		function attrs(names:Array<String>)
			for (n in names) {
				var t = helder.view.Vocabulary.BOOLEANS.indexOf(n) >= 0 ? "boolean" : TYPES.get(n) ?? "unknown";
				if (video) t = ~/\b(ImageFit|Color)\b/g.replace(t, 'import("helder/ui").$1');
				e.line('\t' + n + '?: Value<' + t + '>;');
			}
		function node(tag:String):String {
			var path = helder.view.Vocabulary.node(tag);
			var t = try Context.getType(path) catch (_:Dynamic) null;
			var name = t == null ? null : switch t {
				case TInst(c, _): declared(c.get());
				case _: null;
			}
			return name ?? "Node";
		}
		if (video) {
			var own = events(helder.view.Vocabulary.EVENT_TYPES.get("video"));
			e.line('type Value<T> = T | (() => T);');
			e.line('type UiAttributes = import("helder/ui").Attributes;');
			e.line();
			e.line('// <video> (helder.media.ui.VideoNode): a neutral element\'s attributes and its own');
			e.line('export interface VideoAttributes extends UiAttributes {');
			e.line('\tref?: ((node: ' + node("video") + ') => void) | null;');
			e.line('\tchildren?: never;');
			attrs(helder.view.Vocabulary.OWN["video"]);
			handlers(helder.view.Vocabulary.OWN_EVENTS["video"], own);
			e.line('}');
			e.line();
			e.line('declare global {');
			e.line('\tnamespace JSX {');
			e.line('\t\tinterface IntrinsicElements {');
			e.line('\t\t\tvideo: VideoAttributes;');
			e.line('\t\t}');
			e.line('\t}');
			e.line('}');
			return;
		}
		e.line('// a value, or a function of none that reads it (bound)');
		e.line('type Value<T> = T | (() => T);');
		e.line();
		e.line('// a neutral element\'s attributes (helder.view.Vocabulary): the style');
		e.line('// properties (StyleProps, CSS\'s names in camel), the others HTML\'s and');
		e.line('// helder\'s in camel, ARIA\'s and data-* as HTML writes them, its handlers');
		e.line('// given ui\'s events (' + helder.view.MarkupMacro.NEUTRAL_EVENTS + ')');
		e.line('// a text\'s content: text, values, its spans (elements), what reads them');
		e.line('export type TextContent = string | number | boolean | null | undefined | import("helder/view").View | (() => unknown) | TextContent[];');
		e.line();
		e.line('// (a number\'s also a length as CSS writes one, "12px", "env(safe-area-inset-top)")');
		e.line('export type StyleAttributes = {[K in keyof import("./style").StyleProps]?: Value<import("./style").StyleProps[K] | (number extends import("./style").StyleProps[K] ? string : never)>};');
		e.line();
		e.line('export interface Attributes extends StyleAttributes {');
		e.line('\tkey?: unknown;');
		e.line('\tstyle?: import("./style").StyleProps | null;');
		attrs(helder.view.Vocabulary.COMMON);
		e.line('\t[aria: `aria-$${string}`]: unknown;');
		e.line('\t[data: `data-$${string}`]: unknown;');
		handlers(helder.view.Vocabulary.EVENTS, ui);
		e.line('}');
		// (each primitive's, and a tag's own over its primitive's)
		var kinds = [
			{name: "View", tag: "view", base: null, own: "view"},
			{name: "Scroll", tag: "scroll", base: null, own: "view"},
			{name: "Text", tag: "text", base: null, own: "text"},
			{name: "Image", tag: "image", base: null, own: "image"},
			{name: "Icon", tag: "icon", base: null, own: "icon"},
			{name: "Field", tag: "field", base: null, own: "field"},
			{name: "TextArea", tag: "textarea", base: "Field", own: "textarea"},
			{name: "Glass", tag: "glass", base: null, own: "glass"},
			{name: "WebView", tag: "webview", base: null, own: "webview"},
			{name: "Link", tag: "a", base: "Text", own: "a"},
			{name: "Label", tag: "label", base: "Text", own: "label"}
		];
		for (k in kinds) {
			e.line();
			// (a text area's Enter a new line, no onSubmit)
			var omit = k.tag == "textarea" ? '"ref" | "onSubmit"' : '"ref"';
			e.line('export interface ' + k.name + 'Attributes extends ' + (k.base == null ? "Attributes" : "Omit<" + k.base + "Attributes, " + omit + ">") + ' {');
			e.line('\tref?: ((node: ' + node(k.tag) + ') => void) | null;');
			// (a box's children any content, a text's its text and spans, a leaf's none)
			var content = switch k.tag {
				case "text": "TextContent";
				case "view" | "scroll" | "glass": "unknown";
				case _: "never";
			}
			if (k.base == null) e.line('\tchildren?: ' + content + ';');
			if (helder.view.Vocabulary.OWN.exists(k.own)) attrs(helder.view.Vocabulary.OWN[k.own]);
			var own = helder.view.Vocabulary.OWN_EVENTS.get(k.own);
			if (own != null) handlers(own, ui);
			e.line('}');
		}
		e.line();
		e.line('declare global {');
		e.line('\tnamespace JSX {');
		e.line('\t\t// the neutral elements: ui\'s, realised by each renderer');
		e.line('\t\tinterface IntrinsicElements {');
		var tags = helder.view.Vocabulary.PRIMITIVES.filter(t -> t != "video").concat(sortedTags());
		for (t in tags) {
			var k = Lambda.find(kinds, k -> k.tag == t);
			var b = helder.view.Vocabulary.base(t);
			var name = k != null ? k.name : b == "text" ? "Text" : b == "field" ? "Field" : "View";
			e.line('\t\t\t' + t + ': ' + name + 'Attributes;');
		}
		e.line('\t\t}');
		e.line('\t}');
		e.line('}');
	}

	static function sortedTags():Array<String> {
		var t = [for (k in helder.view.Vocabulary.TAGS.keys()) k];
		t.sort(Reflect.compare);
		return t;
	}

	// (the attributes' values, as TypeScript has them, the booleans
	// Vocabulary.BOOLEANS': unknown else)
	static final TYPES:Map<String, String> = [
		"id" => "string", "class" => "string", "role" => "string", "tabIndex" => "number | string", "slot" => "string", "variant" => "string",
		"size" => "string", "host" => "string", "group" => "string", "peer" => "string", "tag" => "string", "keyContext" => "string",
		"panAxis" => "\"x\" | \"y\" | \"both\"", "panMinPointers" => "number", "matched" => "string", "lang" => "string", "glassSpacing" => "number", "text" => "string",
		"objectFit" => "ImageFit", "objectPosition" => "string", "name" => "string", "value" => "string", "placeholder" => "string", "type" => "string",
		"maxLength" => "number", "inputMode" => "string", "autoComplete" => "string", "keyboard" => "string", "enterKeyHint" => "string",
		"autoCapitalize" => "string", "rows" => "number", "html" => "string", "tint" => "Color | string", "volume" => "number",
		"playbackRate" => "number", "href" => "string", "for" => "string"
	];
}
#end
