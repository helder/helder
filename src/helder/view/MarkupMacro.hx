package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.view.Plan;
import helder.view.Syntax;

using haxe.macro.ExprTools;

// The markup macro: a markup literal (Haxe's parser gives @:markup "<...>",
// the source as written from its "<") is wrapped by the Markup build macro
// (View.literal) and compiled when it is typed, for the renderer that owns
// it (MarkupMacro.literal):
//
//   {var h0:Any = <hole>; ...; new helder.view.View(<renderer>, function(parent, before, out) {...}, ...)}
//
// its holes ({expr} children and attribute values, spreads) evaluated in
// source order where the literal is, and a mount function of direct calls
// to the renderer (Host) and its runtime: each element made by tag, put in
// its parent, its attributes set (static ones and values of a type never
// reactive straight to the renderer, the others through the runtime, which
// binds the reactive ones), its children after it: static text joined at
// compile time, runs of text and holes through the runtime (whether a hole
// is text is known when it runs); components called by the runtime in an
// owner of their own, through a factory (() -> Name({props})), so that
// Haxe checks the props, their children a literal of their own. The
// expressions inside a literal are parsed at their positions in the file
// (errors point into the markup) and wrapped in turn, so markup nests
// through them ({[for (i in items) <text>{i}</text>]}).
//
// The renderer (README, "Renderers in markup"): the literal around it (its
// holes' literals, a component's children unless the component's children
// prop is ViewOf<S>), Render.render's parent, the type expected (ViewOf<R>),
// the enclosing function's return type, its class's one @:renderer; else
// none: the literal is agnostic, its mount code a template in its class's
// metadata, made for each renderer the program reaches after typing
// (HostMacro.late), its factories holes. A class's literals limited to some
// renderers (@:renderer(helder.ui.view.NodeRenderer)): another's code a
// throw; its components, in another renderer's markup, the function of the
// same name of the class it names for that renderer (@:renderer(...,
// helder.web.DomRenderer => DomControls): Pick), else an error naming it
// and the renderer. A function of such a class marked @:neutral is for
// every renderer (a single-source component: its elements the neutral ones,
// view, text, button..., each renderer realising them).
class MarkupMacro {
	// the root (helder.view.Root: RootView), as a literal's renderer: components only, no code to mount
	public static inline final ROOT = "helder.view.Root";
	// the neutral elements' events (view, text, button...): ui's, in every renderer
	public static inline final NEUTRAL_EVENTS = "helder.ui.view.NodeEvents";

	// (the events of a type @:events names: its fields' types by name)
	static final eventSets = new Map<String, Map<String, Type>>();

	// the events a renderer declares (@:events(T): T's fields, each attribute's
	// event type), a neutral element's when tag is given (ui's, and its own:
	// Vocabulary.EVENT_TYPES); null: it declares none
	public static function events(renderer:Null<String>, tag:Null<String>):Null<{of:String, events:Map<String, Type>}> {
		var path = tag != null ? NEUTRAL_EVENTS : renderer == null || renderer == ROOT ? null : HostMacro.info(renderer).events;
		if (path == null) return null;
		var set = eventSet(path);
		var own = tag == null ? null : Vocabulary.EVENT_TYPES.get(Vocabulary.base(tag));
		if (own != null) {
			var all = set.copy();
			for (k => t in eventSet(own))
				all.set(k, t);
			set = all;
		}
		return {of: tag != null ? "<" + tag + "> (its events ui's, " + path + (own == null ? "" : ", and " + own) + ")" : renderer, events: set};
	}

	static function eventSet(path:String):Map<String, Type> {
		var set = eventSets.get(path);
		if (set != null) return set;
		set = new Map();
		switch Context.follow(Context.getType(path)) {
			case TAnonymous(a):
				for (f in a.get().fields)
					set.set(f.name, f.type);
			case t: Context.error('helder.view: @:events($path) is no structure of events (${haxe.macro.TypeTools.toString(t)})', Context.currentPos());
		}
		eventSets.set(path, set);
		return set;
	}

	// the Markup interface's build macro: every field's literals wrapped
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr != null): fn.expr = transform(fn.expr);
				case FVar(t, e) if (e != null): f.kind = FVar(t, transform(e));
				case FProp(g, s, t, e) if (e != null): f.kind = FProp(g, s, t, transform(e));
				case _:
			}
		return fields;
	}

	// e with its markup literals wrapped, to be compiled when typed: for renderer when given (the literal around them's)
	public static function transform(e:Expr, ?renderer:String):Expr
		return switch e.expr {
			case EMeta({name: ":markup"}, {expr: EConst(CString(_))}):
				renderer == null ? macro @:pos(e.pos) helder.view.View.literal($e) : macro @:pos(e.pos) helder.view.View.literalFor($v{renderer}, $e);
			// (wrapped already)
			case ECall({expr: EField(_, "literal" | "literalFor")}, args) if (args.length > 0 && args[args.length - 1].expr.match(EMeta({name: ":markup"}, _))): e;
			// (an interpolated string as what it interpolates, as typing makes it:
			// what reads a signal in '${x()}px' is seen, and the value bound)
			case EConst(CString(s, SingleQuotes)) if (s.indexOf("$") >= 0): transform(haxe.macro.MacroStringTools.formatString(s, e.pos), renderer);
			case _: e.map(x -> transform(x, renderer));
		}

	// content placed in renderer's nodes (Render.render): a literal compiled for it
	public static function place(content:Expr, renderer:String):Expr
		return switch content.expr {
			case EMeta({name: ":markup"}, {expr: EConst(CString(_))}): macro @:pos(content.pos) helder.view.View.literalFor($v{renderer}, $content);
			case ECall({expr: EField(_, "literal")}, [m = {expr: EMeta({name: ":markup"}, _)}]): macro @:pos(content.pos) helder.view.View.literalFor($v{renderer}, $m);
			case EParenthesis(x): place(x, renderer);
			case _: content;
		}

	// a literal being typed (View.literal), for renderer given, else the one where it is
	public static function literal(e:Expr, given:Null<String>):Expr {
		var src = switch e.expr {
			case EMeta(_, {expr: EConst(CString(s))}): s;
			case _: return Context.error("markup: a literal expected", e.pos);
		}
		var info = Context.getPosInfos(e.pos);
		var parser = new Parser(src, (message, at, length) -> Context.error(message, position(info.file, info.min + at, length))), root = parser.document();
		var r = given == null ? placed() : given == ROOT ? ROOT : HostMacro.info(given).path;
		return SourceMap.within(parser.ends, () -> new Plan(new HaxeTarget(info.file, info.min, e.pos), r).compile(root));
	}

	// (the renderer a literal is for from where it is: the type expected, the enclosing
	// function's return type, its class's one @:renderer; null: none, agnostic)
	static function placed():Null<String> {
		var r = HostMacro.viewOf(Context.getExpectedType());
		if (r != null) return r;
		if (neutralMethod()) return null;
		var cls = Context.getLocalClass(), m = Context.getLocalMethod();
		if (cls == null) return null;
		if (m != null) {
			var f = field(cls.get(), m);
			if (f != null)
				r = try switch f.type {
					case TFun(_, ret): HostMacro.pinOf(ret);
					case _: null;
				} catch (_:Dynamic) null;
			if (r != null) return r;
		}
		var l = limits(cls.get().meta);
		return l != null && l.only.length == 1 ? l.only[0] : null;
	}

	static function field(c:ClassType, name:String):Null<ClassField> {
		for (f in c.statics.get())
			if (f.name == name) return f;
		for (f in c.fields.get())
			if (f.name == name) return f;
		return null;
	}

	// (the function being typed is @:neutral: for every renderer, its class's @:renderer aside)
	@:allow(helder.view.HaxeTarget) static function neutralMethod():Bool {
		var cls = Context.getLocalClass(), m = Context.getLocalMethod();
		if (cls == null || m == null) return false;
		var f = field(cls.get(), m);
		return f != null && f.meta.has(":neutral");
	}

	// (a class's @:renderer: the renderers its literals are for, by class path; the class each other one's markup calls instead)
	public static function limits(meta:MetaAccess):Null<{only:Array<String>, other:Map<String, Expr>}> {
		var m = meta.extract(":renderer");
		if (m.length == 0) return null;
		var only = [], other = new Map<String, Expr>();
		for (e in (m[0].params == null ? [] : m[0].params))
			switch e.expr {
				case EBinop(OpArrow, r, c): other.set(HostMacro.resolve(r), c);
				case _: only.push(HostMacro.resolve(e));
			}
		return {only: only, other: other};
	}

	// (the literal being typed's class's limits, unless its function is @:neutral)
	@:allow(helder.view.HaxeTarget) static function ownLimits():Null<{only:Array<String>, other:Map<String, Expr>}> {
		var cls = Context.getLocalClass();
		return cls == null || neutralMethod() ? null : limits(cls.get().meta);
	}

	// a component, its callee typed: its name, its class's limits (unless
	// @:neutral), the renderer its return type pins it to, its children's (a
	// children prop of ViewOf<R>); null when it does not type (the call's error then)
	@:allow(helder.view.HaxeTarget) static function component(callee:Expr):Null<{name:String, field:String, limits:Null<{only:Array<String>, other:Map<String, Expr>}>,
		pin:Null<String>, ret:String, children:Null<String>, reads:Array<String>, childFunction:Bool, childAccessor:Bool}> {
		var t = try Context.typeExpr(callee) catch (_:Dynamic) return null;
		var name = callee.toString(), fieldName = name.split(".").pop(), l = null;
		switch t.expr {
			case TField(_, FStatic(c, cf)):
				name = c.get().name + "." + cf.get().name;
				fieldName = cf.get().name;
				if (!cf.get().meta.has(":neutral")) l = limits(c.get().meta);
			case _:
		}
		var pin = null, ret = "", children = null, reads = [], childFunction = false, childAccessor = false;
		switch Context.follow(t.t) {
			case TFun(args, r):
				pin = HostMacro.pinOf(r);
				ret = haxe.macro.TypeTools.toString(r);
				if (args.length > 0) switch Context.follow(args[0].t) {
					case TAnonymous(a):
						for (f in a.get().fields) {
							if (f.name == "children") {
								children = HostMacro.viewOf(f.type);
								childAccessor = isEither(f.type) && isFunctionType(f.type);
								childFunction = !childAccessor && isFunctionType(f.type);
							}
							if (isRead(f.type)) reads.push(f.name);
						}
					case _:
				}
			case _:
		}
		return {name: name, field: fieldName, limits: l, pin: pin, ret: ret, children: children, reads: reads, childFunction: childFunction,
			childAccessor: childAccessor};
	}

	// (a function's type, through Null and typedefs; an EitherType with a
	// function of one (Show's children, content or its accessor's function))
	static function isFunctionType(t:Type):Bool
		return switch Context.follow(t) {
			case TFun(_, _): true;
			case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): isFunctionType(p);
			case TAbstract(_.get() => {pack: ["haxe", "extern"], name: "EitherType"}, [a, b]): isFunctionType(a) || isFunctionType(b);
			case _: false;
		}

	// (an EitherType of content and a function: its child a function of one, else content)
	static function isEither(t:Type):Bool
		return switch Context.follow(t) {
			case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): isEither(p);
			case TAbstract(_.get() => {pack: ["haxe", "extern"], name: "EitherType"}, _): true;
			case _: false;
		}

	// (helder.view.graph.Read<T>, through Null and typedefs: a prop that reads)
	static function isRead(t:Type):Bool {
		return switch t {
			case TAbstract(_.get() => {pack: ["helder", "view", "graph"], name: "Read"}, _): true;
			case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): isRead(p);
			case TType(_, _): isRead(Context.follow(t, true));
			case TMono(m) if (m.get() != null): isRead(m.get());
			case TLazy(f): isRead(f());
			case _: false;
		}
	}

	// the function renderer's markup calls for callee (Pick.callee): itself, or
	// its class's counterpart for that renderer; none an error
	public static function pick(renderer:String, callee:Expr):Expr {
		var c = component(callee);
		if (c == null || c.limits == null || c.limits.only.indexOf(renderer) >= 0) return callee;
		var o = counterpart(c.limits.other.get(renderer), c.field, callee.pos);
		if (o != null) return o;
		return Context.error("helder.view: " + c.name + " has no version for " + renderer + " (@:renderer names none)", callee.pos);
	}

	static function counterpart(cls:Null<Expr>, field:String, pos:Position):Null<Expr> {
		if (cls == null) return null;
		var has = switch Context.getType(cls.toString()) {
			case TInst(k, _): Lambda.exists(k.get().statics.get(), f -> f.name == field);
			case _: false;
		}
		return has ? macro @:pos(pos) $cls.$field : null;
	}

	// the call of callee for the renderer mounting it (Pick.call): an agnostic
	// literal's, chosen when it runs (Render.pass) among its class's renderers
	public static function pickCall(callee:Expr, props:Expr):Expr {
		var c = component(callee);
		if (c == null || c.limits == null) return macro @:pos(callee.pos) ($callee($props) : Any);
		var cases:Array<Case> = [];
		for (r in c.limits.only)
			cases.push({values: [macro $v{HostMacro.id(r)}], expr: macro @:pos(callee.pos) ($callee($props) : Any)});
		for (r => cls in c.limits.other) {
			var o = counterpart(cls, c.field, callee.pos);
			if (o != null) cases.push({values: [macro $v{HostMacro.id(r)}], expr: macro @:pos(callee.pos) ($o($props) : Any)});
		}
		return {
			expr: ESwitch(macro helder.view.Render.pass, cases, macro @:pos(callee.pos) (throw $v{"helder.view: " + c.name + " has no version for this renderer"} : Any)),
			pos: callee.pos
		};
	}

	// the code made for renderer path: __HOST__ its class, __RT__ its runtime
	// (a reactive attribute with a literal name bound with the renderer's
	// setter for that name, when it has setter: Renders), the neutral
	// elements its own way; late (an agnostic literal's, after typing): what
	// it cannot do a throw, not an error
	public static function forRenderer(body:Array<Expr>, path:String, late:Bool):Array<Expr> {
		var i = HostMacro.info(path);
		var host = path.split("."), rt = HostMacro.runtime(path), setter = i.setter, neutral = i.neutral, native = i.native;
		function sub(e:Expr):Expr
			return switch e.expr {
				// (a neutral element: the renderer's neutral functions, else its own)
				case ECall({expr: EField({expr: EConst(CIdent("__NEUTRAL__"))}, _)}, _) if (!neutral && !native && late):
					macro @:pos(e.pos) (throw $v{"helder.view: " + path + " realises no neutral elements"} : Dynamic);
				case ECall({expr: EField({expr: EConst(CIdent("__NEUTRAL__"))}, _)}, _) if (!neutral && !native):
					Context.error("markup: " + path + " realises no neutral elements (view, text, button...: neutralElement and the rest, or neutralNative)", e.pos);
				case ECall({expr: EField({expr: EConst(CIdent("__NEUTRAL__"))}, f)}, args):
					var a = [for (x in args) sub(x)];
					switch [f, neutral] {
						case ["element", true]: macro @:pos(e.pos) $p{host}.neutralElement(${a[0]});
						// (one the renderer makes with a function of its own, Renders' element_<tag>: <video>, helder.media's)
						case ["element", false] if (a[0].expr.match(EConst(CString(_, _))) && i.creators.indexOf(switch a[0].expr {
								case EConst(CString(t, _)): t;
								case _: "";
							}) >= 0):
							var f = "element_" + switch a[0].expr {
								case EConst(CString(t, _)): t;
								case _: "";
							};
							macro @:pos(e.pos) $p{host}.$f();
						case ["element", false]: macro @:pos(e.pos) $p{host}.createElement(${a[0]});
						case ["property", true]: macro @:pos(e.pos) $p{host}.neutralProperty(${a[0]}, ${a[1]}, ${a[2]}, ${a[3]});
						case ["property", false]: macro @:pos(e.pos) $p{host}.setProperty(${a[0]}, ${a[2]}, ${a[3]});
						// (bound: the setter given the name the realiser chooses, its DOM name for one setter of all)
						case ["prop", true]: macro @:pos(e.pos) $p{rt}.propWith(${a[0]}, $p{host}.neutralName(${a[1]}, ${a[2]}), ${a[3]}, $p{host}.neutralSetter(${a[1]}, ${a[2]}));
						case ["prop", false] if (setter): macro @:pos(e.pos) $p{rt}.propWith(${a[0]}, ${a[2]}, ${a[3]}, $p{host}.setter(${a[2]}));
						case ["prop", false]: macro @:pos(e.pos) $p{rt}.prop(${a[0]}, ${a[2]}, ${a[3]});
						case ["listen", true]: macro @:pos(e.pos) $p{host}.neutralListen(${a[0]}, ${a[1]}, ${a[2]}, ${a[3]});
						case ["listen", false]: macro @:pos(e.pos) $p{host}.listen(${a[0]}, ${a[2]}, ${a[3]});
						case ["part", true]: macro @:pos(e.pos) $p{host}.part(${a[0]});
						case ["part", false]: a[0];
						case _: throw "markup: " + f;
					}
				// (late, an agnostic literal's own element: its attributes may be
				// another renderer's, so a name this one lacks is marked, @:lenient,
				// for its setter to look up at run time: NodeRenderer.setProperty)
				case ECall({expr: EField({expr: EConst(CIdent("__HOST__"))}, "setProperty")}, [el, name = {expr: EConst(CString(_, _))}, v]) if (late && setter):
					macro @:pos(e.pos) $p{host}.setProperty(${sub(el)}, @:lenient $name, ${sub(v)});
				case ECall({expr: EField({expr: EConst(CIdent("__RT__"))}, "prop")}, [el, name = {expr: EConst(CString(s, _))}, v]) if (setter && late):
					macro @:pos(e.pos) $p{rt}.propWith(${sub(el)}, $name, ${sub(v)}, $p{host}.setter(@:lenient $v{s}));
				// (an element of a literal name the renderer makes with a function
				// of its own: that function, Renders' element_<tag>; what it links
				// linked only when markup names it)
				case ECall({expr: EField({expr: EConst(CIdent("__HOST__"))}, "createElement")}, [{expr: EConst(CString(tag, _))}]) if (i.creators.indexOf(tag) >= 0):
					var f = "element_" + tag;
					macro @:pos(e.pos) $p{host}.$f();
				// (an agnostic literal's choice: this renderer's or not, Plan.choose)
				case ECall({expr: EConst(CIdent("__RENDERER__"))}, [{expr: EConst(CString(r, _))}]): macro @:pos(e.pos) $v{r == path};
				case EConst(CIdent("__HOST__")): macro @:pos(e.pos) $p{host};
				case EConst(CIdent("__RT__")): macro @:pos(e.pos) $p{rt};
				case ECall({expr: EField({expr: EConst(CIdent("__RT__"))}, "prop")}, [el, name = {expr: EConst(CString(s, _))}, v]) if (setter):
					macro @:pos(e.pos) $p{rt}.propWith(${sub(el)}, $name, ${sub(v)}, $p{host}.setter($v{s}));
				case EObjectDecl(fields):
					// (copied: a template is made for several renderers; map would lose the fields' name_pos)
					{expr: EObjectDecl([for (f in fields) {var c:Dynamic = Reflect.copy(f); c.expr = sub(f.expr); c;}]), pos: e.pos};
				case _: e.map(sub);
			}
		return [for (e in body) sub(e)];
	}

	// whether an attribute's value may be of a type never reactive, to be
	// told by typing it (plain): an expression of constants, fields,
	// operators and conditions (one with a call, a function or markup in it
	// is left to the runtime to bind or set)
	@:allow(helder.view.HaxeTarget) static function simple(e:Expr):Bool
		return switch e.expr {
			case EConst(_): true;
			case EField(o, _) | EParenthesis(o) | EUnop(_, _, o) | ECheckType(o, _) | ECast(o, null): simple(o);
			case EBinop(_, a, b) | EArray(a, b): simple(a) && simple(b);
			case ETernary(c, a, b) | EIf(c, a, b) if (b != null): simple(c) && simple(a) && simple(b);
			case _: false;
		}

	// whether a value is of a type never reactive (a String, Int, Float or
	// Bool, an enum abstract of one, null of one): set once, as a literal is,
	// not bound (a function, a Signal, Dynamic or a type it cannot tell still
	// bound by the runtime); typed where the literal is
	public static function plain(x:Expr):Bool {
		var t = try Context.typeof(x) catch (_:Dynamic) return false;
		function of(t:haxe.macro.Type):Bool
			return switch Context.follow(t) {
				case TInst(_.get() => {pack: [], name: "String"}, _): true;
				case TAbstract(_.get() => {pack: [], name: "Int" | "Float" | "Bool"}, _): true;
				case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): of(p);
				case TAbstract(_.get() => a, _) if (a.meta.has(":enum")): of(a.type);
				case _: false;
			}
		return of(t);
	}

	// an embedded expression, parsed at its place in the file and its
	// literals wrapped, for renderer when given (null: empty, or only comments)
	@:allow(helder.view.HaxeTarget) static function expr(code:String, file:String, at:Int, renderer:Null<String>, required = false):Null<Expr> {
		if (StringTools.trim(Plan.stripComments(code)) == "") {
			if (required) Context.error("markup: an empty expression", position(file, at - 1, code.length + 2));
			return null;
		}
		var e = Context.parseInlineString(code, position(file, at, code.length));
		return transform(e, renderer);
	}

	public static function position(file:String, min:Int, len:Int):Position
		return Context.makePosition({file: file, min: min, max: min + len});

	static final lineCache = new Map<String, Array<Int>>();

	@:allow(helder.view.HaxeTarget) static function lineOf(file:String, offset:Int):Int {
		var starts = lineCache.get(file);
		if (starts == null) {
			starts = [0];
			var content = try sys.io.File.getContent(file) catch (e:Dynamic) "";
			for (i in 0...content.length)
				if (content.charCodeAt(i) == "\n".code) starts.push(i + 1);
			lineCache.set(file, starts);
		}
		var line = 1;
		for (i in 0...starts.length)
			if (starts[i] <= offset) line = i + 1;
		return line;
	}
}

// The planner's Target for the macro: a literal's code as Haxe expressions
// (__HOST__, __RT__ and __NEUTRAL__ made the renderer's by forRenderer),
// its errors and facts from typing where the literal is
class HaxeTarget implements Target<Expr> {
	final file:String;
	final base:Int;
	final pos:Position;

	public function new(file:String, base:Int, pos:Position) {
		this.file = file;
		this.base = base;
		this.pos = pos;
	}

	function at(where:Null<Where>):Position
		return where == null ? pos : MarkupMacro.position(file, base + where.at, where.length);

	public function error(message:String, where:Null<Where>):Dynamic
		return Context.error(message, at(where));

	public function warning(message:String, where:Where)
		Context.warning(message, at(where));

	public function checked():Bool
		return true;

	public function singleSource():Bool
		return MarkupMacro.neutralMethod();

	// (a function of the node: an untyped parameter typed as it, another checked)
	// (each node's type looked up once a build)
	static final nodes = new Map<String, ComplexType>();

	public function ref(e:Expr, node:String):Expr {
		var ct = nodes.get(node);
		if (ct == null) nodes.set(node, ct = haxe.macro.TypeTools.toComplexType(Context.getType(node)));
		return switch e.expr {
			case EConst(CIdent("null")): e;
			case _: macro @:pos(e.pos) ($e : $ct -> Void);
		}
	}

	public function elements(renderer:String):Null<Array<String>>
		return HostMacro.info(renderer).elements;

	public function props(renderer:String, element:String):Null<Array<String>>
		return HostMacro.props(renderer, element);

	public function code(code:String, at:Int, renderer:Null<String>, required:Bool):Null<Expr>
		return MarkupMacro.expr(code, file, base + at, renderer, required);

	public function isLiteral(e:Expr):Bool
		return e.expr.match(EConst(CInt(_) | CFloat(_) | CString(_, DoubleQuotes)));

	public function isPlain(e:Expr):Bool
		return MarkupMacro.simple(e) && MarkupMacro.plain(e);

	public function mayRead(e:Expr):Bool
		return switch e.expr {
			case EFunction(_, _) | EMeta({name: ":markup"}, _): false;
			// (a literal: its own holes are its own)
			case ECall({expr: EField(_, "literal" | "literalFor")}, args) if (args.length > 0 && args[args.length - 1].expr.match(EMeta({name: ":markup"}, _))): false;
			case ECall(_, _): true;
			// (a value made: it reads what its arguments read; a struct made once, as hxmc passes it)
			case ENew(_, args): Lambda.exists(args, mayRead);
			case EField(o, _): mayRead(o) || getter(e);
			case EArray(a, i): mayRead(a) || mayRead(i) || getter(e);
			case _:
				var r = false;
				e.iter(x -> if (!r && mayRead(x)) r = true);
				r;
		}

	// (a field or an index read through a function: typed where the literal is; one it cannot type may)
	static function getter(e:Expr):Bool {
		if (!MarkupMacro.simple(e)) return true;
		var t = try Context.typeExpr(e) catch (_:Dynamic) return true;
		function calls(t:TypedExpr):Bool
			return switch t.expr {
				case TCall(_, _) | TNew(_, _, _): true;
				case TField(o, FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf)) if (cf.get().kind.match(FVar(AccCall, _))): true;
				case _:
					var r = false;
					haxe.macro.TypedExprTools.iter(t, x -> if (!r && calls(x)) r = true);
					r;
			}
		return calls(t);
	}

	public function thunk(e:Expr):Expr {
		// (a struct value, a Quat: no function returning one may become a
		// function returning Dynamic, as a hole's or a Read's)
		var t = try Context.typeof(e) catch (_:Dynamic) null;
		if (t != null && isStruct(t))
			Context.error("markup: this value is a " + haxe.macro.TypeTools.toString(t)
				+ " (a struct value), which a function returning Dynamic cannot return yet: bind a Signal<" + haxe.macro.TypeTools.toString(t)
				+ ">, or give the renderer typed setters (Renders' @:setters)", e.pos);
		return macro @:pos(e.pos) () -> $e;
	}

	// whether t is a struct value (@:hxmc.struct: Vec3, Quat), through abstracts
	public static function isStruct(t:Type):Bool
		return switch Context.follow(t) {
			case TInst(c, _): c.get().meta.has(":hxmc.struct");
			case TAbstract(_.get() => a, ps) if (a.name != "Null" && !a.meta.has(":coreType")):
				isStruct(haxe.macro.TypeTools.applyTypeParameters(a.type, a.params, ps));
			case _: false;
		}

	public function typedProp(renderer:String, element:String, name:String):Bool
		return HostMacro.info(renderer).setters != null && HostMacro.propType(renderer, element, name) != null;

	public function typedReads(renderer:String, element:String, name:String, value:Expr, reads:Bool):Bool {
		if (reads) return true;
		var want = HostMacro.propType(renderer, element, name);
		var t = try Context.typeof(value) catch (_:Dynamic) return false;
		if (Context.unify(t, want)) return false;
		var of = readerOf(t);
		return of != null && Context.unify(of, want);
	}

	// (a typed prop's value: of its type, or a reader of it: a Signal, a
	// Memo, a function of none; another an error at the attribute)
	public function typedValue(renderer:String, element:String, name:String, value:Expr, reads:Bool, where:Where):Expr {
		var want = HostMacro.propType(renderer, element, name);
		var ct = Context.toComplexType(want);
		var t = try Context.typeof(value) catch (e:Dynamic) Context.error(Std.string(e), value.pos);
		var p = value.pos;
		if (Context.unify(t, want)) return reads ? macro @:pos(p) ((() -> (($value : $ct) : Dynamic)) : Void->Dynamic) : macro @:pos(p) (($value : $ct) : Null<Any>);
		var of = readerOf(t);
		// (a signal's, a memo's or a Read's value read as it is held, boxed:
		// not unboxed and boxed again; a function of none called typed, as a
		// function returning a struct may not be called as one returning Dynamic)
		if (of != null && Context.unify(of, want))
			return isNode(t) ? macro @:pos(p) ((() -> helder.view.Render.read($value)) : Void->Dynamic) : macro @:pos(p) ((() -> (($value() : $ct) : Dynamic)) : Void->Dynamic);
		var tn = haxe.macro.TypeTools.toString(want);
		return Context.error("markup: <" + element + ">'s " + name + " is " + article(tn) + ", not " + article(haxe.macro.TypeTools.toString(t))
			+ (of != null ? " (it reads " + article(haxe.macro.TypeTools.toString(of)) + ")" : ""), at(where));
	}

	// (whether t is a Signal, a Memo or a Read)
	static function isNode(t:Type):Bool
		return switch t {
			case TAbstract(_.get() => {pack: ["helder", "view", "graph"], name: "Signal" | "Memo" | "Read"}, _): true;
			case TAbstract(_.get() => {name: "Null", pack: []}, [x]): isNode(x);
			case TType(_, _) | TLazy(_): isNode(Context.follow(t, true));
			case TMono(m) if (m.get() != null): isNode(m.get());
			case _: false;
		}

	// (what a reader gives: a Signal's, a Memo's, a Read's value, a function of none's result; else null)
	static function readerOf(t:Type):Null<Type>
		return switch t {
			case TAbstract(_.get() => {pack: ["helder", "view", "graph"], name: "Signal" | "Memo" | "Read"}, [v]): v;
			case TAbstract(_.get() => {name: "Null", pack: []}, [x]): readerOf(x);
			case TType(_, _) | TLazy(_): readerOf(Context.follow(t, true));
			case TFun([], r): r;
			case TMono(m) if (m.get() != null): readerOf(m.get());
			case _: null;
		}

	public function typedSet(renderer:String, element:String, name:String, el:Expr, held:Expr, reads:Bool, where:Where):Expr {
		var want = HostMacro.propType(renderer, element, name);
		var ct = Context.toComplexType(want);
		var p = at(where);
		var fn = HostMacro.setterOf(renderer, element, name);
		var setters = HostMacro.info(renderer).setters.split(".");
		var set = (v:Expr) -> fn != null ? macro @:pos(p) $p{fn}($el, ($v : $ct)) : macro @:pos(p) $p{setters}.prop($el, $v{name}, $v);
		if (!reads) return set(macro cast $held);
		var x = set(macro __x);
		return macro @:pos(p) helder.view.graph.Graph.renderEffect((cast $held : Void->Dynamic), (__x:Dynamic) -> $x);
	}

	// a listener checked against its renderer's events (MarkupMacro.events; a
	// neutral element's: ui's): a function of its event or of none, an untyped
	// parameter typed as its event (e -> name(e.text): a String written, not
	// a Dynamic), one of no event given one it ignores (null stays null); a
	// name it does not declare, a value of no static type (Dynamic) or a
	// function of another type an error at the attribute (its name to its
	// value's end). A renderer that declares none (and an agnostic literal's
	// own elements): a function of one argument or none, its event unknown
	public function handler(e:Expr, name:String, renderer:Null<String>, tag:Null<String>, where:Where):Expr {
		var set = MarkupMacro.events(renderer, tag);
		var event:Null<Type> = null;
		if (set != null) {
			event = set.events.get(StringTools.startsWith(name, "on:") ? "on" : name);
			if (event == null) {
				var names = [for (n in set.events.keys()) if (n != "on") n];
				names.sort(Reflect.compare);
				Context.error("markup: " + name + " is no event of " + set.of + " (" + names.join(", ")
					+ (set.events.exists("on") ? "; on:name, a custom one" : "") + ")", at(where));
			}
		}
		var shown = event == null ? null : haxe.macro.TypeTools.toString(Context.follow(event));
		var want = event == null ? "a function of its event or of none" : "a function of " + article(shown) + " or of none (" + shown
			+ " -> Void, or Void -> Void)";
		var gives = event == null ? "" : ", but " + set.of + " gives " + name + " " + article(shown);
		// (from the attribute's name to its value's end)
		var info = Context.getPosInfos(e.pos), from = Context.getPosInfos(at(where));
		var attr = Context.makePosition({file: info.file, min: from.min < info.min ? from.min : info.min, max: info.max});
		switch e.expr {
			case EConst(CIdent("null")): return e;
			// (its parameter untyped: its event's)
			case EFunction(k, f) if (event != null && f.args.length == 1 && f.args[0].type == null):
				var a = f.args[0];
				var ct = haxe.macro.TypeTools.toComplexType(Context.follow(event));
				e = {expr: EFunction(k, {args: [{name: a.name, type: ct, opt: a.opt, meta: a.meta, value: a.value}], ret: f.ret, expr: f.expr, params: f.params}), pos: e.pos};
			case _:
		}
		// (one that does not type: its own error, when its hole is typed)
		var t = try Context.typeof(e) catch (_:Dynamic) return e;
		function params(t:Type):Null<Array<{name:String, opt:Bool, t:Type}>>
			return switch Context.follow(t) {
				case TFun(args, _): args;
				case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): params(p);
				case _: null;
			}
		var args = params(t);
		if (args == null) {
			var noType = Context.follow(t).match(TDynamic(_) | TMono(_));
			return Context.error("markup: " + name + "'s handler is "
				+ (noType ? "of no static type (Dynamic)" : article(haxe.macro.TypeTools.toString(t)) + ", not a function") + ": " + want, attr);
		}
		if (args.length == 0)
			return macro @:pos(e.pos) {
				var __f = $e;
				__f == null ? null : (_:Dynamic) -> __f();
			};
		for (k in 1...args.length)
			if (!args[k].opt) return Context.error("markup: " + name + "'s handler takes " + args.length + " arguments: " + want, attr);
		if (event != null && !Context.unify(event, args[0].t))
			return Context.error("markup: " + name + "'s handler takes " + article(haxe.macro.TypeTools.toString(args[0].t)) + gives + ": " + want, attr);
		return e;
	}

	// ("a String", "an Event")
	static function article(type:String):String
		return (~/^[AEIOU]/.match(type) ? "an " : "a ") + type;

	public function isFunction(e:Expr):Bool
		return switch e.expr {
			case EFunction(_, _): true;
			case EParenthesis(x) | EMeta(_, x) | ECheckType(x, _): isFunction(x);
			case _: false;
		}

	public function arity(e:Expr):Int
		return switch e.expr {
			case EFunction(_, f): f.args.length;
			case EParenthesis(x) | EMeta(_, x) | ECheckType(x, _): arity(x);
			case _: -1;
		}

	public function devKeys():Bool
		return Context.defined("hxmc.dev");

	public function component(name:String, at:Int, renderer:Null<String>):Component<Expr> {
		var p = MarkupMacro.position(file, base + at, name.length + 1);
		var callee:Null<Expr> = null;
		for (part in name.split("."))
			callee = callee == null ? {expr: EConst(CIdent(part)), pos: p} : {expr: EField(callee, part), pos: p};
		var c = MarkupMacro.component(callee);
		if (renderer == Plan.ROOT) {
			if (c != null && c.pin != null && c.pin != renderer)
				Context.error("helder.view: <" + name + "> is " + c.pin + "'s markup (it returns " + c.ret
					+ "), not a root's: a root (UiWindow.run's, Render.open's) holds roots (<Surface>) and components of no renderer", p);
		} else if (renderer != null) {
			var target = MarkupMacro.pick(renderer, callee);
			if (target != callee) {
				callee = target;
				c = MarkupMacro.component(target);
			}
			if (c != null && c.pin == Plan.ROOT)
				Context.error("helder.view: <" + name + "> is a root (it returns " + c.ret + "): UiWindow.run's or Render.open's content, not " + renderer + "'s markup", p);
			if (c != null && c.pin != null && c.pin != renderer)
				Context.error("helder.view: <" + name + "> is " + c.pin + "'s markup (it returns " + c.ret + "), not " + renderer + "'s", p);
		}
		return {callee: callee, children: c != null ? c.children : null, reads: c != null ? c.reads : null, childFunction: c != null && c.childFunction,
			childAccessor: c != null && c.childAccessor};
	}

	public function ident(name:String):Expr
		return macro @:pos(pos) $i{name};

	public function string(s:String, ?where:Where):Expr
		return macro @:pos(at(where)) $v{s};

	public function bool(b:Bool, ?where:Where):Expr
		return macro @:pos(at(where)) $v{b};

	public function nil():Expr
		return macro @:pos(pos) null;

	public function isNull(e:Expr):Bool
		return e.expr.match(EConst(CIdent("null")));

	public function anyArray(items:Array<Expr>):Expr
		return macro @:pos(pos) ([$a{items}] : Array<Null<Any>>);

	public function declare(name:String, e:Expr, where:Null<Where>):Expr
		return macro @:pos(at(where)) var $name = $e;

	public function call(of:Callee, name:String, args:Array<Expr>, where:Null<Where>):Expr {
		var o = switch of {
			case Host: "__HOST__";
			case Runtime: "__RT__";
			case Neutral: "__NEUTRAL__";
		}
		var p = at(where);
		return {expr: ECall({expr: EField({expr: EConst(CIdent(o)), pos: p}, name), pos: p}, args), pos: p};
	}

	public function holeDecl(name:String, e:Expr, factory:Bool):Expr
		return {expr: EVars([{name: name, type: factory ? macro :Void->Null<Any> : macro :Null<Any>, expr: e}]), pos: e.pos};

	public function holeRef(name:String, e:Expr):Expr
		return macro @:pos(e.pos) $i{name};

	public function callValue(f:Expr):Expr
		return macro @:pos(pos) $f();

	public function partRef(element:Expr, ref:Expr, where:Where):Expr
		return macro @:pos(at(where)) {
			var r:Dynamic = $ref;
			if (r != null) (r : Dynamic -> Void)(__NEUTRAL__.part($element));
		};

	public function keyScope(name:String, key:Expr):Expr
		return macro @:pos(pos) $v{name + "["} + Std.string($key) + "]";

	public function factory(c:Component<Expr>, props:Array<{name:String, value:Expr, at:Int}>, content:Null<Expr>, at:Int, agnostic:Bool):Expr {
		var callee = c.callee, p = callee.pos;
		var fields:Array<ObjectField> = [];
		for (a in props) {
			// (name_pos: the field name's position, which the compiler reads though ObjectField does not declare it)
			var field:Dynamic = {
				field: a.name,
				expr: a.value,
				quotes: ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(a.name) ? Unquoted : Quoted,
				name_pos: MarkupMacro.position(file, base + a.at, a.name.length)
			};
			fields.push(field);
		}
		if (content != null) fields.push({field: "children", expr: content});
		var props = {expr: EObjectDecl(fields), pos: p};
		var call = agnostic ? macro @:pos(p) helder.view.Pick.call($callee, $props) : {expr: ECall(callee, [props]), pos: p};
		return {expr: EFunction(FAnonymous, {args: [], ret: macro :Any, expr: SourceMap.factory({expr: EReturn(call), pos: p}, callee, file, base, at)}), pos: p};
	}

	// (__RENDERER__: whether the literal is made for that renderer, forRenderer's constant)
	public function choose(renderer:String, then:Array<Expr>, otherwise:Array<Expr>):Array<Expr>
		return [macro @:pos(pos) if (__RENDERER__($v{renderer})) $b{then} else $b{otherwise}];

	// (read when compiled: Svg.parse of a constant)
	public function drawing(text:String, where:Where):Expr
		return macro @:pos(at(where)) helder.canvas.Svg.parse($v{text});

	public function clones(renderer:String):Bool
		return HostMacro.info(renderer).clones;

	// (keyed by the element's place in its file: one template a site)
	public function template(name:String, at:Int, make:Array<Expr>, built:String):Null<Expr> {
		var key = file + ":" + (base + at);
		// (one block: the template's declaration in scope of its return)
		var body = {expr: EBlock(make.concat([macro return $i{built}])), pos: pos};
		var f = {expr: EFunction(FAnonymous, {args: [], ret: null, expr: body}), pos: pos};
		return macro @:pos(pos) var $name = __RT__.cloneOf($v{key}, $f);
	}

	public function view(v:Planned<Expr>):Expr {
		var holes = v.holes, body = v.body, renderer = v.renderer;
		var parts = v.parts == null ? macro null : macro function():Array<Null<Any>> return ([$a{v.parts}] : Array<Null<Any>>);
		var line = MarkupMacro.lineOf(file, base);
		var source = haxe.io.Path.withoutDirectory(file) + ":" + line;
		// (a root's: its parts only, no code to mount)
		if (renderer == Plan.ROOT)
			return macro @:pos(pos) $b{holes.concat([macro @:pos(pos) new helder.view.View($v{HostMacro.id(Plan.ROOT)}, null, 0, null, $parts, $v{source})])};
		var own = MarkupMacro.ownLimits(), cls = Context.getLocalClass();
		if (renderer == null) {
			// (its template in its class, made for each renderer after typing: HostMacro.late)
			var key = HostMacro.id(file + ":" + base + ":" + v.at);
			var decls = [
				for (h in v.holeNames)
					{expr: EVars([{name: h.name, type: h.factory ? macro :Void->Null<Any> : macro :Null<Any>, expr: null}]), pos: pos}
			];
			var only = own == null ? [] : [for (r in own.only) macro $v{r}];
			if (cls == null) Context.error("markup: a literal outside a class", pos);
			// (and the field it is in: its code kept only if that field is, where DCE can tell, JavaScript)
			var m = Context.getLocalMethod(), c = cls.get();
			var feature = m == null ? "" : c.pack.concat([c.name, m]).join(".");
			c.meta.add(":helder.late", [macro $v{key}, macro $b{decls}, macro $b{body}, macro $a{only}, macro $v{feature}], pos);
			var hs = [for (h in v.holeNames) macro $i{h.name}];
			return macro @:pos(pos) $b{holes.concat([macro @:pos(pos) new helder.view.View(0, null, $v{key}, ([$a{hs}] : Array<Null<Any>>), $parts, $v{source})])};
		}
		var info = HostMacro.reach(renderer);
		var code = own != null && own.only.indexOf(renderer) < 0 ? [
			macro @:pos(pos) throw $v{"helder.view: " + cls.get().name + " markup is not for " + renderer + " (@:renderer)"}
		] : MarkupMacro.forRenderer(body, renderer, false);
		var n = info.node;
		var mount = macro function(__p0:Dynamic, __b0:Dynamic, __o0:Dynamic):Void {
			var __p:$n = cast __p0;
			var __b:Null<$n> = cast __b0;
			var __o:Null<Array<$n>> = cast __o0;
			$b{code};
		};
		return macro @:pos(pos) $b{holes.concat([macro @:pos(pos) new helder.view.View($v{info.id}, $mount, 0, null, $parts, $v{source})])};
	}

	// (dev builds and headless runs: an element told where it is written, helder.view.Source;
	// last in the file, so that a release build's positions of the code above stay the same)
	public function located(element:Expr, at:Int):Null<Expr>
		return SourceMap.element(element, file, base, at, pos);

	// (live literals: LiveMacro; last in the file, the positions of the code above unmoved)
	public function liveOn():Bool
		return LiveMacro.on();

	public function live(value:Expr, at:helder.view.Plan.LiveAt):Null<Expr>
		return LiveMacro.live(value, at, file, base);

	public function liveIn(e:Expr):Expr
		return LiveMacro.liveIn(e, file);
}
#end
