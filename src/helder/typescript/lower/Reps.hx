package helder.typescript.lower;

import haxe.ds.Vector;
import hxmc.ir.Ir;
import helder.typescript.check.Types;
import helder.typescript.check.Types.TsType;
import helder.typescript.ir.Builder;
import helder.typescript.lower.Classes.ClassLayout;

// An object type's layout: the object literals of these keys in this
// order whose values are of these representations, made as objects of an
// hxmc class of their own under the runtime's JsObject, their properties
// in typed slots; and the object types they are made for (each literal's
// own type and its contextual type), whose property accesses guard on it.
// Structural typing lets any object arrive where such a type is: the
// guard is the class (and that the instance was not deopted, JsObject.DEOPT).
class ObjectLayout {
	public final index:Int;
	public final names:Array<String>;
	public final tys:Array<Ty>;
	public final info:ClassInfo;
	public final types:Map<Int, Bool> = [];
	// (the global holding its runtime Layout, made at startup)
	public final global:Int;

	public function new(index, names, tys, info, global) {
		this.index = index;
		this.names = names;
		this.tys = tys;
		this.info = info;
		this.global = global;
	}
}

// What values look like in compiled code, by their TypeScript types: a
// number is an F64, an instance of a class with a layout is that class's
// hxmc object, an array the runtime's JsArray; anything else is a dynamic
// value (Dynamic, the runtime's JS values). A typed slot (a binding, a
// parameter, a result, a field) holds what its type says: a value enters
// it through store, which checks it and throws (TSHX100) where the types
// do not describe the program's values.
class Reps {
	final p:Program;
	final types:Types;
	final classes:Classes;
	final layouts:Map<ClassInfo, ClassLayout> = [];
	public final arrayClass:ClassInfo;
	final holeClass:ClassInfo;
	public final objectBase:ClassInfo;
	// (the runtime's Layout, as JsObject's field holds it)
	public final layoutType:Ty;
	var link:Null<FuncInfo> = null;
	// (property sites: js.Sites' records, and object literals' shapes, each
	// a global made by startup, run when the program starts)
	final siteClass:ClassInfo;
	final shapeClass:ClassInfo;
	public final startup:FuncInfo;
	final records:Array<{global:Int, key:String, ?keys:Array<String>}> = [];
	final literals:Map<String, Int> = [];
	// (object types' layouts, by keys and representations; by key; Object.prototype at startup)
	public final objects:Array<ObjectLayout> = [];
	final objectKeys:Map<String, ObjectLayout> = [];
	final objectsByName:Map<String, Array<ObjectLayout>> = [];
	var objectProto = -1;

	public function new(p:Program, types:Types, classes:Classes) {
		this.p = p;
		this.types = types;
		this.classes = classes;
		arrayClass = runtimeClass("helder.typescript.js.JsArray");
		holeClass = runtimeClass("helder.typescript.js.Hole");
		objectBase = runtimeClass("helder.typescript.js.JsObject");
		layoutType = TRef(RObj(runtimeClass("helder.typescript.js.Layout")));
		siteClass = runtimeClass("helder.typescript.js.Site");
		shapeClass = runtimeClass("helder.typescript.js.Shape");
		startup = Builder.func(p, "sites", TVoid);
		if (classes.all.length == 0) return;
		for (fn in p.funcs) if (fn.name == "helder_typescript_js_Seed_libTypedClass") link = fn;
		if (link == null) throw "TSHX004: runtime helper not linked: libTypedClass";
		// (the hxmc classes first, then their fields: a field's type can be any of them)
		for (c in classes.all) {
			var sup = c.parent == null ? objectBase : c.parent.info;
			var ci = new ClassInfo("ts.C" + c.index + "_" + c.name, "ts_class" + c.index + "_" + ~/[^A-Za-z0-9_]/g.replace(c.name, "_"), sup);
			ci.ifaces = sup.ifaces.copy();
			ci.derived = sup.derived.copy();
			p.classes.push(ci);
			c.info = ci;
			layouts.set(ci, c);
		}
		for (c in classes.all) {
			c.info.fields = c.info.sup.fields.copy();
			for (name in c.names) c.info.fields.push({name: "ts_field" + c.info.fields.length, ty: rep(name.tsType)});
		}
	}

	function runtimeClass(name:String):ClassInfo {
		for (c in p.classes) if (c.name == name) return c;
		throw "TSHX004: runtime class not linked: " + name;
	}

	// ---- representations

	public function rep(t:Null<TsType>):Ty {
		if (types.isNumber(t)) return TF64;
		if (types.isBoolean(t)) return TBool;
		if (types.isString(t)) return TRef(RStr);
		if (types.isArray(t)) return TRef(RObj(arrayClass));
		var c = t == null || t.isThis ? null : classes.of(types.instanceOf(t));
		return c == null ? TRef(RAny) : TRef(RObj(c.info));
	}

	// the class with a layout whose instances a type's values are (its `this` type's too)
	public function layoutOf(t:Null<TsType>):Null<ClassLayout> return classes.of(types.instanceOf(t));

	// a value into a slot of type t: checked where its own type does not prove it
	public function store(b:Builder, e:Ex, t:Ty, where:String):Ex {
		var from = Ir.typeOf(e);
		if (Type.enumEq(from, t)) return e;
		return switch [from, t] {
			case [TI32, TF64]: EConv(I2F, e);
			case [_, TF64]: b.runtime("expectNumber", [b.coerce(e, TRef(RAny)), EStr(where)]);
			case [_, TBool]: b.runtime("expectBoolean", [b.coerce(e, TRef(RAny)), EStr(where)]);
			case [_, TRef(RStr)]: b.runtime("expectString", [b.coerce(e, TRef(RAny)), EStr(where)]);
			case [TRef(RObj(d)), TRef(RObj(c))] if (isA(d, c)): ECast(t, e);
			case [_, TRef(RObj(c))]:
				var v = b.temp(b.coerce(e, TRef(RAny)));
				b.out.push(SIf(ENot(EInstOf(c, v)), b.block(() -> b.runtime("diverge", [EStr(describe(c)), v, EStr(where)])), new Vector(0)));
				ECast(t, v);
			case _: b.coerce(e, t);
		}
	}

	function isA(d:ClassInfo, c:ClassInfo):Bool {
		var k = d;
		while (k != null) {
			if (k == c) return true;
			k = k.sup;
		}
		return false;
	}

	function describe(c:ClassInfo):String return c == arrayClass ? "an array" : "an instance of " + layouts.get(c).name;

	// whether a value is statically of class c (no test needed)
	public function exact(e:Ex, c:ClassInfo):Bool return switch Ir.typeOf(e) {
		case TRef(RObj(d)): isA(d, c);
		case _: false;
	}

	// (if the value is of class c: fast, else slow)
	function guarded(b:Builder, o:Ex, c:ClassInfo, fast:() -> Void, slow:() -> Void) {
		if (exact(o, c)) fast();
		else b.out.push(SIf(EInstOf(c, o), b.block(fast), b.block(slow)));
	}

	// ---- fields of classes with layouts
	// a field's slot in its class's hxmc class (and in its subclasses')
	public function slot(c:ClassLayout, name:String):Int return objectBase.fields.length + c.fields().indexOf(name);

	public function fieldGet(b:Builder, c:ClassLayout, obj:Ex, name:String, where:String):Ex {
		var i = slot(c, name), ty = c.info.fields[i].ty;
		var l = b.local("field", ty);
		var o = exact(obj, c.info) ? obj : b.temp(b.coerce(obj, TRef(RAny)));
		guarded(b, o, c.info, () -> b.out.push(SSet(l, EField(c.info, i, ECast(TRef(RObj(c.info)), o)))),
			() -> b.out.push(SSet(l, store(b, b.runtime("libGet", [o, EStr(name)]), ty, where))));
		return ELocal(l);
	}

	public function fieldSet(b:Builder, c:ClassLayout, o:Ex, name:String, v:Ex, where:String) {
		var i = slot(c, name);
		guarded(b, o, c.info, () -> b.out.push(SSetField(c.info, i, ECast(TRef(RObj(c.info)), o), store(b, v, c.info.fields[i].ty, where))),
			() -> b.runtime("libPut", [b.coerce(o, TRef(RAny)), EStr(name), b.coerce(v, TRef(RAny))]));
	}

	// (a class's value: its layout, by field number, and its allocator)
	public function linkClass(b:Builder, c:ClassLayout, cls:Ex) {
		var ci = c.info, names = c.fields();
		var self = TRef(RObj(ci));
		var tys = [for (a in link.args) a.ty];
		var get = linkLambda(b, closureSig(tys[2]), (b, args) -> {
			var o = b.temp(ECast(self, ELocal(args[0])));
			for (k in 0...names.length)
				b.out.push(SIf(EBin(Eq, ELocal(args[1]), EInt(k)), b.block(() -> b.out.push(SReturn(b.coerce(EField(ci, slot(c, names[k]), o), TRef(RAny))))), new Vector(0)));
			b.out.push(SReturn(b.runtime("getUndefined", [])));
		});
		var set = linkLambda(b, closureSig(tys[3]), (b, args) -> {
			var o = b.temp(ECast(self, ELocal(args[0])));
			for (k in 0...names.length) {
				var i = slot(c, names[k]);
				b.out.push(SIf(EBin(Eq, ELocal(args[1]), EInt(k)), b.block(() -> b.out.push(SSetField(ci, i, o, store(b, ELocal(args[2]), ci.fields[i].ty, c.name + "." + names[k])))), new Vector(0)));
			}
			b.out.push(SReturn(null));
		});
		var alloc = linkLambda(b, closureSig(tys[4]), (b, args) -> b.out.push(SReturn(b.coerce(allocate(b, c, ELocal(args[0])), closureSig(tys[4]).ret))));
		var elem = switch tys[1] {
			case TRef(RArr(t)): t;
			case t: throw "TSHX004: not an array type: " + t;
		};
		b.runtime("libTypedClass", [cls, ENewArr(elem, Vector.fromArrayCopy([for (f in names) b.coerce(EStr(f), elem)])), get, set, alloc]);
	}

	// a new instance of a class with a layout, with its prototype and layout (its fields
	// not yet initialized: dynamic ones undefined, typed ones set before they are read)
	public function allocate(b:Builder, c:ClassLayout, proto:Ex):Ex {
		var ci = c.info;
		// (zeroed: an extensible object without own properties; JsObject's constructor would set only its prototype)
		var o = b.temp(ENewObj(ci));
		var base = ECast(TRef(RObj(objectBase)), o);
		var p = objectBase.fieldIndex("proto");
		b.out.push(SSetField(objectBase, p, base, b.coerce(proto, objectBase.fields[p].ty)));
		// (its shapes' root: its layout's, once the class is made)
		var layout = b.temp(ECast(layoutType, EGlobal(c.layout, TRef(RAny))));
		var lc = switch layoutType {
			case TRef(RObj(l)): l;
			case t: throw "TSHX004: not a class type: " + t;
		};
		when(b, EBin(RefNe, layout, ENull(layoutType)),
			() -> b.out.push(SSetField(objectBase, objectBase.fieldIndex("shape"), base, EField(lc, lc.fieldIndex("root"), layout))));
		for (f in c.fields()) {
			var i = slot(c, f);
			if (ci.fields[i].ty.match(TRef(RAny))) b.out.push(SSetField(ci, i, o, b.runtime("getUndefined", [])));
		}
		return o;
	}

	// a function of the runtime's type (a closure of signature s) built here
	function linkLambda(outer:Builder, s:SigInfo, build:(Builder, Array<Local>) -> Void):Ex {
		var f = Builder.func(p, "layout" + p.funcs.length, s.ret);
		f.args = [new Local(0, "closure", TRef(RAny))].concat([for (i in 0...s.args.length) new Local(i + 1, "a" + i, s.args[i])]);
		var li = new LambdaInfo(p.lambdas.length, s, new Vector(0), f);
		p.lambdas.push(li);
		f.lambda = li;
		var b = new Builder(p, f);
		build(b, f.args.slice(1));
		b.finish();
		return outer.temp(ENewClos(li, new Vector(0)));
	}

	static function closureSig(t:Ty):SigInfo return switch t {
		case TRef(RClos(s)): s;
		case _: throw "TSHX004: not a function type: " + t;
	}

	// ---- property sites (js.Sites): `o.name`, `o.name = v`, `o.name(...)`

	function runtimeFn(name:String):FuncInfo {
		for (fn in p.funcs) if (fn.name == "helder_typescript_js_Seed_" + name) return fn;
		throw "TSHX004: runtime helper not linked: " + name;
	}

	// a new site's record
	public function site(key:String):Ex {
		var g = p.globals.length;
		p.globals.push({ty: TRef(RObj(siteClass)), init: null, name: "ts_site" + g});
		records.push({global: g, key: key});
		return EGlobal(g, TRef(RObj(siteClass)));
	}

	// an object literal's shape: its keys (distinct), in order
	public function literalShape(keys:Array<String>):Ex {
		var tag = keys.join("\x00");
		if (!literals.exists(tag)) {
			var g = p.globals.length;
			p.globals.push({ty: TRef(RObj(shapeClass)), init: null, name: "ts_shape" + g});
			records.push({global: g, key: null, keys: keys});
			literals.set(tag, g);
		}
		return EGlobal(literals.get(tag), TRef(RObj(shapeClass)));
	}

	// (the records made, once the program is lowered)
	public function finishSites() {
		var b = new Builder(p, startup);
		if (objectProto >= 0) b.out.push(SSetGlobal(objectProto, b.runtime("libObjectProto", [])));
		for (o in objects) linkObject(b, o);
		for (r in records) {
			if (r.keys == null) {
				b.out.push(SSetGlobal(r.global, b.runtime("libSiteOf", [EStr(r.key)])));
				continue;
			}
			var elem = switch runtimeFn("libShape").args[0].ty {
				case TRef(RArr(t)): t;
				case t: throw "TSHX004: not an array type: " + t;
			};
			b.out.push(SSetGlobal(r.global, b.runtime("libShape", [b.temp(ENewArr(elem, Vector.fromArrayCopy([for (k in r.keys) b.coerce(EStr(k), elem)])))])));
		}
		b.out.push(SReturn(null));
		b.finish();
	}

	// (o an ordinary object whose shape is the site's: then with it and the site)
	function sameShape(b:Builder, o:Ex, site:Ex, hit:(Ex, Ex) -> Void) {
		when(b, EInstOf(objectBase, o), () -> {
			var obj = b.temp(ECast(TRef(RObj(objectBase)), o));
			var s = b.temp(site);
			when(b, EBin(RefEq, EField(objectBase, objectBase.fieldIndex("shape"), obj), EField(siteClass, siteClass.fieldIndex("shape"), s)), () -> hit(obj, s));
		});
	}

	// `o.name`: an own data property by the site's shape, else the site's stub
	public function siteGet(b:Builder, o:Ex, key:String):Ex {
		var site = this.site(key);
		var obj = b.temp(b.coerce(o, TRef(RAny)));
		var l = b.local("property", TRef(RAny)), hit = b.local("hit", TBool);
		b.out.push(SSet(hit, ECast(TBool, EInt(0))));
		sameShape(b, obj, site, (jo, s) -> {
			b.out.push(SSet(l, EArrGet(TRef(RAny), EField(objectBase, objectBase.fieldIndex("slots"), jo), EField(siteClass, siteClass.fieldIndex("slot"), s))));
			b.out.push(SSet(hit, ECast(TBool, EInt(1))));
		});
		when(b, ENot(ELocal(hit)), () -> b.out.push(SSet(l, b.runtime("libGetAt", [obj, site]))));
		return ELocal(l);
	}

	// `o.name = v`: a writable own data property by the site's shape, else the site's stub
	public function sitePut(b:Builder, o:Ex, key:String, v:Ex) {
		var site = this.site(key);
		var obj = b.temp(b.coerce(o, TRef(RAny)));
		var value = b.temp(b.coerce(v, TRef(RAny)));
		var hit = b.local("hit", TBool);
		b.out.push(SSet(hit, ECast(TBool, EInt(0))));
		sameShape(b, obj, site, (jo, s) -> {
			var values = b.local("values", objectBase.fields[objectBase.fieldIndex("slots")].ty);
			b.out.push(SSet(values, EField(objectBase, objectBase.fieldIndex("slots"), jo)));
			b.out.push(SArrSet(TRef(RAny), values, EField(siteClass, siteClass.fieldIndex("slot"), s), value));
			b.out.push(SSet(hit, ECast(TBool, EInt(1))));
		});
		when(b, ENot(ELocal(hit)), () -> b.runtime("libPutAt", [obj, site, value]));
	}

	// `o.name(...)`: the site's stub, then the call
	public function siteCall(b:Builder, o:Ex, key:String, args:Ex):Ex
		return b.runtime("libCallAt", [b.coerce(o, TRef(RAny)), site(key), args]);

	// ---- object types' layouts (ObjectLayout)

	// the layout of these keys and representations (made once)
	public function objectLayout(names:Array<String>, tys:Array<Ty>):ObjectLayout {
		var tag = [for (i in 0...names.length) names[i] + ":" + Std.string(tys[i])].join(",");
		var o = objectKeys.get(tag);
		if (o != null) return o;
		var i = objects.length;
		var ci = new ClassInfo("ts.O" + i, "ts_object" + i, objectBase);
		ci.ifaces = objectBase.ifaces.copy();
		ci.derived = objectBase.derived.copy();
		ci.fields = objectBase.fields.copy();
		for (t in tys) ci.fields.push({name: "ts_field" + ci.fields.length, ty: t});
		p.classes.push(ci);
		var g = p.globals.length;
		p.globals.push({ty: TRef(RAny), init: null, name: "ts_object_layout" + g});
		o = new ObjectLayout(i, names, tys, ci, g);
		objects.push(o);
		objectKeys.set(tag, o);
		for (n in names) objectsByName.set(n, (objectsByName.get(n) ?? []).concat([o]));
		return o;
	}

	// (a type and a union's members: the type ids an object's type may be)
	static function typeIds(t:Null<TsType>):Array<Int> return t == null ? [] : t.members != null ? [for (m in t.members) m.id] : [t.id];

	// the object layouts whose instances a value of type t may be, having key
	public function objectCandidates(t:Null<TsType>, key:String):Array<ObjectLayout> {
		var ids = typeIds(t);
		if (ids.length == 0) return [];
		var out = [for (o in objectsByName.get(key) ?? []) if (makes(o, ids)) o];
		return out.length > 3 ? out.slice(0, 3) : out;
	}

	// (whether o's literals are values of one of these types: made for it, or assignable to it)
	function makes(o:ObjectLayout, ids:Array<Int>):Bool {
		for (id in ids) {
			if (o.types.exists(id)) return true;
			for (s in o.types.keys()) if (types.assignableTo(s, id)) return true;
		}
		return false;
	}

	// the one object layout a type's values are made by, else null
	public function objectOf(t:Null<TsType>):Null<ObjectLayout> {
		var ids = typeIds(t);
		var found:Null<ObjectLayout> = null;
		for (o in objects) if (makes(o, ids)) {
			if (found != null) return null;
			found = o;
		}
		return found;
	}

	public function objectSlot(o:ObjectLayout, key:String):Int return objectBase.fields.length + o.names.indexOf(key);

	// (whether v, of the runtime's values, is what a slot of type t takes)
	function fits(b:Builder, v:Ex, t:Ty):Ex return switch t {
		case TF64: b.runtime("libIsNumber", [v]);
		case TBool: b.runtime("libIsBoolean", [v]);
		case TRef(RStr): b.runtime("libIsString", [v]);
		case TRef(RObj(c)): EInstOf(c, v);
		case _: ECast(TBool, EInt(1));
	}

	// (v, which fits t, as t)
	function fitted(b:Builder, v:Ex, t:Ty):Ex return t == TF64 ? b.runtime("libNumber", [v]) : b.coerce(v, t);

	// (its runtime Layout: by number, its slots as the runtime's values; a
	// value a slot does not take deopts the instance, then is written as any)
	function linkObject(b:Builder, o:ObjectLayout) {
		var ci = o.info, self = TRef(RObj(ci));
		var tys = [for (a in runtimeFn("libObjectLayout").args) a.ty];
		var get = linkLambda(b, closureSig(tys[1]), (b, args) -> {
			var obj = b.temp(ECast(self, ELocal(args[0])));
			for (k in 0...o.names.length)
				b.out.push(SIf(EBin(Eq, ELocal(args[1]), EInt(k)), b.block(() -> b.out.push(SReturn(b.coerce(EField(ci, objectSlot(o, o.names[k]), obj), TRef(RAny))))), new Vector(0)));
			b.out.push(SReturn(b.runtime("getUndefined", [])));
		});
		var set = linkLambda(b, closureSig(tys[2]), (b, args) -> {
			var obj = b.temp(ECast(self, ELocal(args[0])));
			var v = ELocal(args[2]);
			for (k in 0...o.names.length) {
				var i = objectSlot(o, o.names[k]), t = o.tys[k];
				b.out.push(SIf(EBin(Eq, ELocal(args[1]), EInt(k)), b.block(() -> {
					b.out.push(SIf(fits(b, v, t), b.block(() -> b.out.push(SSetField(ci, i, obj, fitted(b, v, t)))), b.block(() -> {
						b.runtime("libDeopt", [ECast(TRef(RObj(objectBase)), obj)]);
						b.runtime("libPut", [ELocal(args[0]), EStr(o.names[k]), v]);
					})));
					b.out.push(SReturn(null));
				}), new Vector(0)));
			}
			b.out.push(SReturn(null));
		});
		var elem = switch tys[0] {
			case TRef(RArr(t)): t;
			case t: throw "TSHX004: not an array type: " + t;
		};
		b.out.push(SSetGlobal(o.global, b.runtime("libObjectLayout", [ENewArr(elem, Vector.fromArrayCopy([for (f in o.names) b.coerce(EStr(f), elem)])), get, set])));
	}

	// a new instance of o, its slots these values (each of its slot's type)
	public function objectNew(b:Builder, o:ObjectLayout, values:Array<Ex>):Ex {
		if (objectProto < 0) {
			objectProto = p.globals.length;
			p.globals.push({ty: TRef(RAny), init: null, name: "ts_object_proto" + objectProto});
		}
		var ci = o.info;
		var obj = b.temp(ENewObj(ci));
		var base = ECast(TRef(RObj(objectBase)), obj);
		var pi = objectBase.fieldIndex("proto");
		b.out.push(SSetField(objectBase, pi, base, b.coerce(EGlobal(objectProto, TRef(RAny)), objectBase.fields[pi].ty)));
		var lc = switch layoutType {
			case TRef(RObj(l)): l;
			case t: throw "TSHX004: not a class type: " + t;
		};
		b.out.push(SSetField(objectBase, objectBase.fieldIndex("shape"), base, EField(lc, lc.fieldIndex("root"), ECast(layoutType, EGlobal(o.global, TRef(RAny))))));
		for (k in 0...o.names.length) b.out.push(SSetField(ci, objectSlot(o, o.names[k]), obj, values[k]));
		return obj;
	}

	// (whether v fits slot type t whatever its value: no test)
	public function fitsStatically(v:Ex, t:Ty):Bool {
		var from = Ir.typeOf(v);
		if (Type.enumEq(from, t) || t.match(TRef(RAny)) || from == TI32 && t == TF64) return true;
		return switch [from, t] {
			case [TRef(RObj(d)), TRef(RObj(c))]: isA(d, c);
			case _: false;
		}
	}

	// (v of the runtime's values into slot type t where it fits: then with it as t)
	public function ifFits(b:Builder, v:Ex, t:Ty, then:Ex->Void, otherwise:() -> Void) {
		var from = Ir.typeOf(v);
		if (Type.enumEq(from, t) || t.match(TRef(RAny))) {
			then(b.coerce(v, t));
			return;
		}
		if (from == TI32 && t == TF64) {
			then(EConv(I2F, v));
			return;
		}
		switch [from, t] {
			case [TRef(RObj(d)), TRef(RObj(c))] if (isA(d, c)):
				then(ECast(t, v));
				return;
			case _:
		}
		var any = b.temp(b.coerce(v, TRef(RAny)));
		b.out.push(SIf(fits(b, any, t), b.block(() -> then(fitted(b, any, t))), b.block(otherwise)));
	}

	// (o, of the runtime's values, an instance of l still laid out: then with it as one)
	function laidOut(b:Builder, o:Ex, l:ObjectLayout, then:Ex->Void) {
		when(b, EInstOf(l.info, o), () -> {
			var obj = b.temp(ECast(TRef(RObj(l.info)), o));
			var bits = EField(objectBase, objectBase.fieldIndex("bits"), ECast(TRef(RObj(objectBase)), obj));
			when(b, EBin(Eq, EBin(And, bits, EInt(16)), EInt(0)), () -> then(obj));
		});
	}

	// `o.key` where o's type's values may be the candidates' instances: their
	// slot as want (TF64: those whose slot is a number), else slow(the site's value)
	public function objectGet(b:Builder, o:Ex, key:String, candidates:Array<ObjectLayout>, want:Ty, slow:Ex->Ex):Ex {
		var obj = b.temp(b.coerce(o, TRef(RAny)));
		var l = b.local("property", want), done = b.local("laid", TBool);
		b.out.push(SSet(done, ECast(TBool, EInt(0))));
		for (c in candidates) {
			var t = c.tys[c.names.indexOf(key)];
			if (want == TF64 && t != TF64) continue;
			when(b, ENot(ELocal(done)), () -> laidOut(b, obj, c, lo -> {
				b.out.push(SSet(l, b.coerce(EField(c.info, objectSlot(c, key), lo), want)));
				b.out.push(SSet(done, ECast(TBool, EInt(1))));
			}));
		}
		when(b, ENot(ELocal(done)), () -> b.out.push(SSet(l, slow(siteGet(b, obj, key)))));
		return ELocal(l);
	}

	// `o.key` as a number where it is a candidate's number slot (num set),
	// else as the site reads it (any)
	public function objectGetEither(b:Builder, o:Ex, key:String, candidates:Array<ObjectLayout>):{num:Local, f:Local, any:Local} {
		var obj = b.temp(b.coerce(o, TRef(RAny)));
		var num = b.local("isNumber", TBool), f = b.local("number", TF64), d = b.local("property", TRef(RAny));
		b.out.push(SSet(num, ECast(TBool, EInt(0))));
		for (c in candidates) if (c.tys[c.names.indexOf(key)] == TF64)
			when(b, ENot(ELocal(num)), () -> laidOut(b, obj, c, lo -> {
				b.out.push(SSet(f, EField(c.info, objectSlot(c, key), lo)));
				b.out.push(SSet(num, ECast(TBool, EInt(1))));
			}));
		when(b, ENot(ELocal(num)), () -> b.out.push(SSet(d, siteGet(b, obj, key))));
		return {num: num, f: f, any: d};
	}

	// `o.key = v`: into the slot of the candidate o is an instance of, where v fits it; else the site's way
	public function objectSet(b:Builder, o:Ex, key:String, candidates:Array<ObjectLayout>, v:Ex) {
		var obj = b.temp(b.coerce(o, TRef(RAny)));
		var value = Ir.typeOf(v) == TF64 || Ir.typeOf(v) == TBool ? b.temp(v) : b.temp(b.coerce(v, Ir.typeOf(v).match(TRef(_)) ? Ir.typeOf(v) : TRef(RAny)));
		var done = b.local("laid", TBool);
		b.out.push(SSet(done, ECast(TBool, EInt(0))));
		for (c in candidates) {
			var i = objectSlot(c, key), t = c.tys[c.names.indexOf(key)];
			when(b, ENot(ELocal(done)), () -> laidOut(b, obj, c, lo -> ifFits(b, value, t, x -> {
				b.out.push(SSetField(c.info, i, lo, x));
				b.out.push(SSet(done, ECast(TBool, EInt(1))));
			}, () -> {})));
		}
		when(b, ENot(ELocal(done)), () -> sitePut(b, obj, key, value));
	}

	// (o exactly an instance of l: laid out, nothing beyond its slots; then with it as one)
	public function exactly(b:Builder, o:Ex, l:ObjectLayout, then:Ex->Void) {
		when(b, EInstOf(l.info, o), () -> {
			var obj = b.temp(ECast(TRef(RObj(l.info)), o));
			var shape = EField(objectBase, objectBase.fieldIndex("shape"), ECast(TRef(RObj(objectBase)), obj));
			var lc = switch layoutType {
				case TRef(RObj(x)): x;
				case t: throw "TSHX004: not a class type: " + t;
			};
			when(b, EBin(RefEq, shape, EField(lc, lc.fieldIndex("root"), ECast(layoutType, EGlobal(l.global, TRef(RAny))))), () -> then(obj));
		});
	}

	// ---- arrays: length, and elements by number

	public function arrayLength(b:Builder, o:Ex):Ex {
		var l = b.local("length", TF64);
		guarded(b, o, arrayClass, () -> b.out.push(SSet(l, EField(arrayClass, arrayClass.fieldIndex("length"), ECast(TRef(RObj(arrayClass)), o)))),
			() -> b.out.push(SSet(l, b.coerce(b.runtime("libGet", [b.coerce(o, TRef(RAny)), EStr("length")]), TF64))));
		return ELocal(l);
	}

	// (an element stored densely at a number index, not a hole: hit with the
	// items and the index; otherwise miss, the runtime's way)
	function denseElement(b:Builder, o:Ex, k:Ex, hit:(Local, Ex) -> Void, miss:() -> Void) {
		var found = b.local("dense", TBool);
		b.out.push(SSet(found, ECast(TBool, EInt(0))));
		function inside() {
			var items = b.local("items", TRef(RArr(TRef(RAny))));
			b.out.push(SSet(items, EField(arrayClass, arrayClass.fieldIndex("items"), ECast(TRef(RObj(arrayClass)), o))));
			when(b, EBin(FGe, k, EF64(0)), () -> when(b, EBin(FLt, k, EConv(I2F, EArrLen(ELocal(items)))), () -> {
				var i = b.temp(EConv(F2I, k));
				when(b, EBin(FEq, EConv(I2F, i), k), () -> {
					var v = b.temp(EArrGet(TRef(RAny), ELocal(items), i));
					when(b, ENot(EInstOf(holeClass, v)), () -> {
						b.out.push(SSet(found, ECast(TBool, EInt(1))));
						hit(items, i);
					});
				});
			}));
		}
		if (exact(o, arrayClass)) inside(); else when(b, EInstOf(arrayClass, o), inside);
		when(b, ENot(ELocal(found)), miss);
	}

	static function when(b:Builder, cond:Ex, then:() -> Void) b.out.push(SIf(cond, b.block(then), new Vector(0)));

	// ---- number arrays (JsArray's nums: the elements unboxed while each is a number)

	public function numberArray(b:Builder, elements:Array<Ex>):Ex
		return ECast(TRef(RObj(arrayClass)), b.runtime("libNumberArray", [ENewArr(TF64, Vector.fromArrayCopy([for (e in elements) b.coerce(e, TF64)]))]));

	// (o's nums when o is a number array: hit with them and a flag it sets
	// where it did what it does; else, or where it did not, miss)
	function numbers(b:Builder, o:Ex, hit:(Ex, Local) -> Void, miss:() -> Void) {
		var done = b.local("unboxed", TBool);
		b.out.push(SSet(done, ECast(TBool, EInt(0))));
		function inside() {
			var nums = b.temp(EField(arrayClass, arrayClass.fieldIndex("nums"), ECast(TRef(RObj(arrayClass)), o)));
			when(b, EBin(RefNe, nums, ENull(Ir.typeOf(nums))), () -> hit(nums, done));
		}
		if (exact(o, arrayClass)) inside(); else when(b, EInstOf(arrayClass, o), inside);
		when(b, ENot(ELocal(done)), miss);
	}

	// (k, a number or a loop's Int64 counter, an index of nums: then with it as an Int)
	static function inRange(b:Builder, nums:Ex, k:Ex, then:Ex->Void) {
		if (Ir.typeOf(k) == TI64) when(b, EBin(LGe, k, EConv(I2L, EInt(0))), () -> when(b, EBin(LLt, k, EConv(I2L, EArrLen(nums))), () -> then(b.temp(EConv(L2I, k)))));
		else if (Ir.typeOf(k) == TI32) when(b, EBin(Ge, k, EInt(0)), () -> when(b, EBin(Lt, k, EArrLen(nums)), () -> then(k)));
		else when(b, EBin(FGe, k, EF64(0)), () -> when(b, EBin(FLt, k, EConv(I2F, EArrLen(nums))), () -> {
			var i = b.temp(EConv(F2I, k));
			when(b, EBin(FEq, EConv(I2F, i), k), () -> then(i));
		}));
	}

	static function yes(b:Builder, flag:Local) b.out.push(SSet(flag, ECast(TBool, EInt(1))));

	// `a[k]` of a number array as a number: the element where a is a number
	// array and k one of its indices, else miss(the element as the runtime reads it)
	public function arrayGetNumber(b:Builder, o:Ex, k:Ex, miss:Ex->Ex):Ex {
		var l = b.local("number", TF64);
		numbers(b, o, (nums, done) -> inRange(b, nums, k, i -> {
			b.out.push(SSet(l, EArrGet(TF64, nums, i)));
			yes(b, done);
		}), () -> b.out.push(SSet(l, miss(arrayGet(b, o, index(b, k))))));
		return ELocal(l);
	}

	static function index(b:Builder, k:Ex):Ex return Ir.typeOf(k) == TI32 ? EConv(I2F, k) : Ir.typeOf(k) == TI64 ? b.temp(EConv(L2F, k)) : k;

	// `a[k] = v` with v a number: in place where a is a number array and k one
	// of its indices or its length (a is extensible), else as any write
	public function arraySetNumber(b:Builder, o:Ex, k:Ex, v:Ex) {
		var value = b.temp(b.coerce(v, TF64));
		numbers(b, o, (nums, done) -> {
			var local = switch nums {
				case ELocal(l): l;
				case _: throw "TSHX004: nums not in a local";
			};
			inRange(b, nums, k, i -> {
				b.out.push(SArrSet(TF64, local, i, value));
				yes(b, done);
			});
			// (one past the end, and the array extensible: appended)
			var bits = objectBase.fieldIndex("bits");
			var extensible = EBin(Eq, EBin(And, EField(objectBase, bits, ECast(TRef(RObj(objectBase)), o)), EInt(1)), EInt(0));
			when(b, ENot(ELocal(done)), () -> when(b, EBin(FEq, index(b, k), EConv(I2F, EArrLen(nums))), () -> when(b, extensible, () -> {
				b.out.push(SArrPush(TF64, local, value));
				b.out.push(SSetField(arrayClass, arrayClass.fieldIndex("length"), ECast(TRef(RObj(arrayClass)), o), EConv(I2F, EArrLen(nums))));
				yes(b, done);
			})));
		}, () -> arraySet(b, o, index(b, k), value));
	}

	public function arrayGet(b:Builder, o:Ex, k:Ex):Ex {
		var l = b.local("element", TRef(RAny));
		denseElement(b, o, k, (items, i) -> b.out.push(SSet(l, EArrGet(TRef(RAny), ELocal(items), i))),
			() -> b.out.push(SSet(l, b.runtime("libGet", [b.coerce(o, TRef(RAny)), b.coerce(k, TRef(RAny))]))));
		return ELocal(l);
	}

	public function arraySet(b:Builder, o:Ex, k:Ex, v:Ex) {
		var value = b.temp(b.coerce(v, TRef(RAny)));
		denseElement(b, o, k, (items, i) -> b.out.push(SArrSet(TRef(RAny), items, i, value)),
			() -> b.runtime("libPut", [b.coerce(o, TRef(RAny)), b.coerce(k, TRef(RAny)), value]));
	}
}
