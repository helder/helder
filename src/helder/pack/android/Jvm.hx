package helder.pack.android;

import helder.pack.android.ClassFile;
import helder.pack.android.Dalvik;
import helder.pack.android.Dex;

// JVM bytecode translated to Dalvik's, as d8 does for minSdk 29 (helder's
// floor; default and static interface methods stay, in a version 037 file):
// - the operand stack's words become registers (the stack's below the
//   locals', the arguments last, as Dalvik passes them); a load is an
//   alias of the local's register until something writes it, a result
//   stored straight into a local is written there, a value popped is not
//   moved: most of javac's loads and stores cost no instruction;
// - the types at each instruction are inferred over words (StackMapTable's
//   frames where the class has them), for the moves' kinds, a byte or a
//   boolean array's aget and aput, the handlers' states;
// - try ranges become try items (each range's handlers in the table's
//   order), a handler a move-exception (its own stub when code also falls
//   or jumps into it);
// - invokedynamic of LambdaMetafactory (metafactory, altMetafactory's
//   markers and bridges) becomes a synthetic class (<host>$$ExternalSyntheticLambda<n>)
//   whose method calls the implementation (a private lambda$ body made
//   package-private, an instance one static with its receiver first; a
//   private method or constructor through a static accessor), adapting
//   arguments (casts, boxing, unboxing, widening); StringConcatFactory a
//   StringBuilder; a synchronized method's lock explicit (monitor-enter, a
//   catch-all that releases it); multianewarray Array.newInstance;
// - nests (Java 11's private access between a class and its inner ones):
//   a nest's private instance methods made static with their receiver
//   first (every call to them invoke-static: no dispatch changes), its
//   other private members package-private (`prepare`, before translating);
// - jsr and ret are not translated: a method that cannot be throws a
//   RuntimeException when called (`stubs` says why).
class Jvm {
	final lookup:String->Null<ClassFile>;

	// the methods made stubs: "<class>.<method><desc>: why"
	public final stubs:Array<String> = [];

	// private members made reachable: owner.name+desc to true (an instance
	// method made static, its receiver first) or false (package-private)
	final relaxed = new Map<String, Bool>();
	final prepared = new Map<String, Bool>();

	public function new(lookup:String->Null<ClassFile>) {
		this.lookup = lookup;
	}

	// a class's private members other classes call: its nest's, its lambdas'
	// bodies (every class translated is prepared before any is translated)
	public function prepare(c:ClassFile) {
		if (prepared.exists(c.name)) return;
		prepared.set(c.name, true);
		var nest = c.nestHost != null || c.nestMembers.length > 0;
		if (nest) {
			for (m in c.methods)
				if (m.access & ClassFile.PRIVATE != 0) relaxed.set(c.name + "." + m.name + m.desc, m.name != "<init>" && m.access & ClassFile.STATIC == 0);
		}
		for (b in c.bootstraps) {
			if (b.method.owner != "java/lang/invoke/LambdaMetafactory" || b.args.length < 2) continue;
			switch b.args[1] {
				case CHandle(h) if (h.owner == c.name && StringTools.startsWith(h.name, "lambda$")):
					var m = c.method(h.name, h.desc);
					if (m != null && m.access & ClassFile.PRIVATE != 0) relaxed.set(c.name + "." + h.name + h.desc, m.access & ClassFile.STATIC == 0);
				case _:
			}
		}
	}

	// null: not relaxed; true: made static with its receiver; false: package-private
	public function relaxedOf(owner:String, name:String, desc:String):Null<Bool>
		return relaxed.get(owner + "." + name + desc);

	// whether a method is private (and still so) in its class
	public function isPrivate(owner:String, name:String, desc:String):Bool {
		if (relaxed.exists(owner + "." + name + desc)) return false;
		var c = lookup(owner);
		var m = c == null ? null : c.method(name, desc);
		return m != null && m.access & ClassFile.PRIVATE != 0;
	}

	// a nest's private fields are package-private
	function fieldAccess(c:ClassFile, f:JField):Int {
		var a = f.access & 0xffff;
		return c.nestHost != null || c.nestMembers.length > 0 ? a & ~ClassFile.PRIVATE : a;
	}

	public static function desc(name:String):String
		return name.charAt(0) == "[" ? name : "L" + name + ";";

	public static function internal(d:String):String
		return d.charAt(0) == "L" ? d.substr(1, d.length - 2) : d;

	// a method descriptor's parameters and return type
	public static function signature(d:String):{params:Array<String>, ret:String} {
		var params = [], k = 1;
		while (d.charAt(k) != ")") {
			var s = k;
			while (d.charAt(k) == "[")
				k++;
			if (d.charAt(k) == "L") k = d.indexOf(";", k);
			k++;
			params.push(d.substring(s, k));
		}
		return {params: params, ret: d.substr(k + 1)};
	}

	public static inline function wide(t:String):Bool
		return t == "J" || t == "D";

	// a type on the stack: int-like ones are I
	public static function stackType(t:String):String
		return switch t {
			case "Z" | "B" | "C" | "S": "I";
			case _: t;
		}

	public static function isRef(t:String):Bool {
		var c = t.charAt(0);
		return c == "L" || c == "[" || c == "N" || c == "T" || c == "U" || c == "R";
	}

	public static function merge(a:String, b:String):String {
		if (a == b) return a;
		if (a == "X" || b == "X" || !isRef(a) || !isRef(b)) return "X";
		if (a == "N") return b;
		if (b == "N") return a;
		var ua = a == "T" || a.charAt(0) == "U", ub = b == "T" || b.charAt(0) == "U";
		return ua || ub ? "X" : "R";
	}

	// the UTF-16 units in ClassFile's form of a string
	public static function escape(units:Array<Int>):String {
		var s = new StringBuf();
		for (u in units)
			if (u >= 2 && u < 0x80) s.addChar(u) else {
				s.addChar(1);
				s.add(StringTools.hex(u, 4));
			}
		return s.toString();
	}

	// dex's access flags of a method
	static function methodAccess(m:JMethod):Int {
		var a = m.access & 0xffff;
		if (a & ClassFile.SYNCHRONIZED != 0 && a & ClassFile.NATIVE == 0) a = (a & ~ClassFile.SYNCHRONIZED) | 0x20000;
		if (m.name == "<init>" || m.name == "<clinit>") a |= Dex.CONSTRUCTOR;
		return a;
	}

	static function value(c:Null<JConst>):Null<DexValue>
		return switch c {
			case null: null;
			case CInt(v): VInt(v);
			case CFloat(b): VFloat(b);
			case CLong(h, l): VLong(h, l);
			case CDouble(h, l): VDouble(h, l);
			case CString(s): VString(s);
			case _: null;
		}

	// ---- a class

	// the class's dex form (the methods and fields kept: all by default)
	// and the lambda classes of its invokedynamics
	public function translate(c:ClassFile, ?keepMethod:JMethod->Bool, ?keepField:JField->Bool):Array<DexClass> {
		var host = new Host(this, c);
		var out:DexClass = {
			name: desc(c.name),
			access: c.access & (0x1 | 0x10 | 0x200 | 0x400 | 0x1000 | 0x2000 | 0x4000),
			superName: c.superName == null ? null : desc(c.superName),
			interfaces: [for (i in c.interfaces) desc(i)],
			fields: [for (f in c.fields) if (keepField == null || keepField(f)) {
				name: f.name,
				type: f.desc,
				access: fieldAccess(c, f),
				value: f.access & ClassFile.STATIC != 0 ? value(f.value) : null
			}],
			methods: []
		};
		prepare(c);
		for (e in c.inner)
			if (e.name == c.name) {
				// (dalvik's system annotations, what Class.getSimpleName and getEnclosingClass read)
				out.annotations = [
					{
						type: "Ldalvik/annotation/InnerClass;",
						visibility: 2,
						elements: [
							{name: "accessFlags", value: VInt(e.access)},
							{name: "name", value: e.simple == null ? VNull : VString(e.simple)}
						]
					}
				];
				var outer = e.outer ?? c.enclosing;
				if (outer != null) out.annotations.push({type: "Ldalvik/annotation/EnclosingClass;", visibility: 2, elements: [{name: "value", value: VType(desc(outer))}]});
			}
		var kept = [for (m in c.methods) if (keepMethod == null || keepMethod(m)) m];
		for (m in kept) {
			var s = signature(m.desc), access = methodAccess(m), params = s.params;
			var r = relaxedOf(c.name, m.name, m.desc);
			if (r != null) {
				access = (access & ~ClassFile.PRIVATE) | (r ? ClassFile.STATIC : 0);
				if (r) params = [desc(c.name)].concat(params);
			}
			var dm:DexMethod = {name: m.name, ret: s.ret, params: params, access: access};
			if (m.code != null) dm.code = try new Method(host, m).translate() catch (e:haxe.Exception) {
				stubs.push(c.name + "." + m.name + m.desc + ": " + e.message);
				stub(m, params, access & ClassFile.STATIC != 0, e.message);
			};
			out.methods.push(dm);
		}
		for (a in host.accessors)
			out.methods.push(a);
		return [out].concat(host.lambdas);
	}

	// a method that throws: new RuntimeException("<why>")
	static function stub(m:JMethod, params:Array<String>, isStatic:Bool, why:String):DexCode {
		var ins = isStatic ? 0 : 1;
		for (p in params)
			ins += wide(p) ? 2 : 1;
		var a = new Dalvik();
		a.ref(0x22, 0, RType("Ljava/lang/RuntimeException;"));
		a.string(1, "helder: " + m.name + " not translated (" + why + ")");
		a.invoke(Dalvik.INVOKE_DIRECT, [0, 1], RMethod("Ljava/lang/RuntimeException;", "<init>", "V", ["Ljava/lang/String;"]));
		a.raw([0x27]);
		return a.code(2 + ins, ins, 2);
	}

	final supertypes = new Map<String, Map<String, Bool>>();

	// whether a value of type `from` (a descriptor) is one of `to`, as far as
	// the classes seen tell (false when they cannot)
	public function assignable(from:String, to:String):Bool {
		if (from == to || to == "Ljava/lang/Object;" && isRef(from) && from != "T" && from.charAt(0) != "U") return true;
		if (from.charAt(0) != "L" || to.charAt(0) != "L") return false;
		return supers(internal(from)).exists(internal(to));
	}

	function supers(name:String):Map<String, Bool> {
		var m = supertypes.get(name);
		if (m != null) return m;
		m = [name => true];
		supertypes.set(name, m);
		var c = lookup(name);
		if (c != null) for (s in (c.superName == null ? [] : [c.superName]).concat(c.interfaces))
			for (k in supers(s).keys())
				m.set(k, true);
		return m;
	}
}

// one class's translation: its lambdas, accessors and relaxed methods
private class Host {
	public final jvm:Jvm;
	public final c:ClassFile;
	public final lambdas:Array<DexClass> = [];
	public final accessors:Array<DexMethod> = [];
	// private implementations called through an accessor: name + desc to the accessor's name
	final through = new Map<String, String>();

	public function new(jvm:Jvm, c:ClassFile) {
		this.jvm = jvm;
		this.c = c;
	}

	// the static accessor of a private method or constructor of the class
	// a lambda calls (one not relaxed: Jvm.prepare), made once: its name
	function accessor(h:JHandle, m:JMethod):String {
		var key = h.name + h.desc, made = through.get(key);
		if (made != null) return made;
		var name = "access$lambda$" + accessors.length, s = Jvm.signature(h.desc), self = Jvm.desc(c.name);
		var isStatic = m.access & ClassFile.STATIC != 0, ctor = h.name == "<init>";
		var params = (isStatic || ctor ? [] : [self]).concat(s.params);
		var a = new Dalvik(), words = 0;
		for (p in params)
			words += Jvm.wide(p) ? 2 : 1;
		// (a constructor's: a new object in v0, the arguments after it)
		var base = ctor ? 1 : 0, regs = [for (k in 0...words) base + k];
		if (ctor) a.ref(0x22, 0, RType(self));
		var call = ctor ? [0].concat(regs) : regs;
		a.invoke(isStatic ? Dalvik.INVOKE_STATIC : Dalvik.INVOKE_DIRECT, call, RMethod(self, h.name, s.ret, s.params));
		var ret = ctor ? self : s.ret;
		if (ctor) a.raw([0x11]) else switch ret {
			case "V": a.raw([0x0e]);
			case "J" | "D":
				a.raw([0x0b]);
				a.raw([0x10]);
			case t if (t.charAt(0) == "L" || t.charAt(0) == "["):
				a.raw([0x0c]);
				a.raw([0x11]);
			case _:
				a.raw([0x0a]);
				a.raw([0x0f]);
		}
		// (room for the result: a long's two registers)
		var registers = base + words, need = Jvm.wide(ret) ? 2 : ret == "V" ? 0 : 1;
		accessors.push({
			name: name,
			ret: ret,
			params: params,
			access: ClassFile.STATIC | ClassFile.SYNTHETIC,
			code: a.code(registers > need ? registers : need, words, call.length)
		});
		through.set(key, name);
		return name;
	}

	// the method a lambda's class calls for its implementation (kind, owner, name, desc)
	public function implementation(h:JHandle):JHandle {
		var r = jvm.relaxedOf(h.owner, h.name, h.desc);
		if (r == true) return {kind: 6, owner: h.owner, name: h.name, desc: "(" + Jvm.desc(h.owner) + h.desc.substr(1), iface: h.iface};
		var m = h.owner == c.name ? c.method(h.name, h.desc) : null;
		if (m == null || !jvm.isPrivate(c.name, h.name, h.desc)) return h;
		var self = Jvm.desc(c.name);
		var d = h.name == "<init>" ? "(" + h.desc.substring(1, h.desc.indexOf(")")) + ")" + self : m.access & ClassFile.STATIC != 0 ? h.desc : "("
			+ self + h.desc.substr(1);
		return {kind: 6, owner: h.owner, name: accessor(h, m), desc: d, iface: false};
	}

	// the class of one lambda (its fields the captured values, its method the interface's)
	public function lambda(name:String, captured:Array<String>, iface:String, sam:String, samDescs:Array<String>, markers:Array<String>,
			impl:JHandle):DexClass {
		var self = "L" + name + ";";
		var fields = [for (k in 0...captured.length) {name: "f$" + k, type: captured[k], access: ClassFile.PRIVATE | ClassFile.FINAL | ClassFile.SYNTHETIC}];
		var methods:Array<DexMethod> = [];
		// <init>: v0 the object's copy, v1-v2 a value's; this and the values after
		{
			var a = new Dalvik(), ins = 1;
			for (t in captured)
				ins += Jvm.wide(t) ? 2 : 1;
			var me = 3, at = me + 1;
			a.invoke(Dalvik.INVOKE_DIRECT, [me], RMethod("Ljava/lang/Object;", "<init>", "V", []));
			for (k in 0...captured.length) {
				var t = captured[k];
				Emit.iput(a, at, me, t, RField(self, "f$" + k, t));
				at += Jvm.wide(t) ? 2 : 1;
			}
			a.raw([0x0e]);
			methods.push({
				name: "<init>",
				ret: "V",
				params: captured,
				access: ClassFile.PUBLIC | Dex.CONSTRUCTOR | ClassFile.SYNTHETIC,
				code: a.code(3 + ins, ins, 1)
			});
		}
		var target = implementation(impl);
		var ctorOwner = target.kind == 8 ? Jvm.desc(target.owner) : null;
		var ts = Jvm.signature(target.desc);
		var implParams = (target.kind == 5 || target.kind == 7 || target.kind == 9 ? [Jvm.desc(target.owner)] : []).concat(ts.params);
		var block = ctorOwner != null ? 1 : 0;
		for (p in implParams)
			block += Jvm.wide(p) ? 2 : 1;
		for (sd in samDescs) {
			var s = Jvm.signature(sd), a = new Dalvik();
			var ins = 1;
			for (p in s.params)
				ins += Jvm.wide(p) ? 2 : 1;
			var me = 4 + block, slot = 4, arg = me + 1;
			if (ctorOwner != null) {
				a.ref(0x22, slot, RType(ctorOwner));
				slot++;
			}
			if (captured.length + s.params.length != implParams.length) throw 'lambda: ${captured.length} captured and ${s.params.length} arguments for ${implParams.length}';
			for (k in 0...captured.length) {
				var t = captured[k];
				Emit.iget(a, slot, me, t, RField(self, "f$" + k, t));
				slot += Jvm.wide(t) ? 2 : 1;
			}
			for (k in 0...s.params.length) {
				var from = s.params[k], to = implParams[captured.length + k];
				Emit.adapt(a, arg, from, slot, to);
				arg += Jvm.wide(from) ? 2 : 1;
				slot += Jvm.wide(to) ? 2 : 1;
			}
			var regs = [for (k in 4...4 + block) k];
			var op = switch target.kind {
				case 6: Dalvik.INVOKE_STATIC;
				case 9: Dalvik.INVOKE_INTERFACE;
				case 7 | 8: Dalvik.INVOKE_DIRECT;
				case _: target.iface ? Dalvik.INVOKE_INTERFACE : Dalvik.INVOKE_VIRTUAL;
			};
			a.invoke(op, regs, RMethod(Jvm.desc(target.owner), target.name, ts.ret, ts.params));
			var result = ctorOwner != null ? ctorOwner : ts.ret;
			if (ctorOwner == null && result != "V") a.raw([(Jvm.wide(result) ? 0x0b : result.length > 1 ? 0x0c : 0x0a)]);
			var resultReg = ctorOwner != null ? 4 : 0;
			if (s.ret == "V") a.raw([0x0e]) else {
				Emit.adapt(a, resultReg, result, 2, s.ret);
				a.raw([Jvm.wide(s.ret) ? 0x10 | 2 << 8 : s.ret.length > 1 ? 0x11 | 2 << 8 : 0x0f | 2 << 8]);
			}
			methods.push({
				name: sam,
				ret: s.ret,
				params: s.params,
				access: ClassFile.PUBLIC | ClassFile.FINAL | ClassFile.SYNTHETIC,
				code: a.code(4 + block + ins, ins, block < 2 ? 2 : block)
			});
		}
		var l:DexClass = {
			name: self,
			access: ClassFile.FINAL | ClassFile.SYNTHETIC,
			superName: "Ljava/lang/Object;",
			interfaces: [for (k => i in [iface].concat(markers)) if ([iface].concat(markers).indexOf(i) == k) Jvm.desc(i)],
			fields: fields,
			methods: methods
		};
		lambdas.push(l);
		return l;
	}
}

// small sequences the lambdas' classes use (registers under 16 through v0-v3)
private class Emit {
	static function moveOp(t:String):Int
		return Jvm.wide(t) ? 0x04 : t.length > 1 ? 0x07 : 0x01;

	public static function move(a:Dalvik, dst:Int, src:Int, t:String) {
		if (dst == src) return;
		var op = moveOp(t);
		if (dst < 16 && src < 16) a.raw([op | dst << 8 | src << 12]) else if (dst < 256) a.raw([op + 1 | dst << 8, src]) else a.raw([op + 2, dst, src]);
	}

	static function fieldOp(t:String):Int
		return switch t.charAt(0) {
			case "J" | "D": 1;
			case "L" | "[": 2;
			case "Z": 3;
			case "B": 4;
			case "C": 5;
			case "S": 6;
			case _: 0;
		}

	public static function iget(a:Dalvik, dst:Int, obj:Int, t:String, f:DRef) {
		if (dst < 16 && obj < 16) {
			a.ref(0x52 + fieldOp(t), dst | obj << 4, f);
			return;
		}
		move(a, 0, obj, "L");
		a.ref(0x52 + fieldOp(t), 1 | 0 << 4, f);
		move(a, dst, 1, t);
	}

	public static function iput(a:Dalvik, src:Int, obj:Int, t:String, f:DRef) {
		if (src < 16 && obj < 16) {
			a.ref(0x59 + fieldOp(t), src | obj << 4, f);
			return;
		}
		move(a, 0, obj, "L");
		move(a, 1, src, t);
		a.ref(0x59 + fieldOp(t), 1 | 0 << 4, f);
	}

	static final WRAPPERS = [
		"Z" => "Boolean", "B" => "Byte", "C" => "Character", "S" => "Short", "I" => "Integer", "J" => "Long", "F" => "Float", "D" => "Double"
	];
	static final UNWRAP = [
		"Ljava/lang/Boolean;" => "Z", "Ljava/lang/Byte;" => "B", "Ljava/lang/Character;" => "C", "Ljava/lang/Short;" => "S",
		"Ljava/lang/Integer;" => "I", "Ljava/lang/Long;" => "J", "Ljava/lang/Float;" => "F", "Ljava/lang/Double;" => "D"
	];
	static final NAMES = [
		"Z" => "boolean", "B" => "byte", "C" => "char", "S" => "short", "I" => "int", "J" => "long", "F" => "float", "D" => "double"
	];

	static function regs(r:Int, t:String):Array<Int>
		return Jvm.wide(t) ? [r, r + 1] : [r];

	// a value of type from in src, as type to in dst (v0-v3 used)
	public static function adapt(a:Dalvik, src:Int, from:String, dst:Int, to:String) {
		var refFrom = from.length > 1, refTo = to.length > 1;
		if (from == to || (refFrom && refTo && to == "Ljava/lang/Object;")) {
			move(a, dst, src, from);
			return;
		}
		if (refFrom && refTo) {
			move(a, dst, src, from);
			a.ref(0x1f, dst, RType(to));
			return;
		}
		if (!refFrom && refTo) {
			var w = "Ljava/lang/" + WRAPPERS.get(from) + ";";
			a.invoke(Dalvik.INVOKE_STATIC, regs(src, from), RMethod(w, "valueOf", w, [from]));
			a.raw([0x0c | 3 << 8]);
			if (UNWRAP.get(to) == null && to != "Ljava/lang/Object;" && to != "Ljava/lang/Number;") a.ref(0x1f, 3, RType(to));
			move(a, dst, 3, to);
			return;
		}
		if (refFrom && !refTo) {
			var p = UNWRAP.get(from) ?? to, w = "Ljava/lang/" + WRAPPERS.get(p) + ";";
			move(a, 3, src, from);
			a.ref(0x1f, 3, RType(w));
			a.invoke(Dalvik.INVOKE_VIRTUAL, [3], RMethod(w, NAMES.get(p) + "Value", p, []));
			a.raw([(Jvm.wide(p) ? 0x0b : 0x0a) | 0 << 8]);
			widen(a, 0, p, to);
			move(a, dst, 0, to);
			return;
		}
		move(a, 0, src, from);
		widen(a, 0, from, to);
		move(a, dst, 0, to);
	}

	// a primitive in v0(-v1) widened in place to another (int-likes are ints)
	static function widen(a:Dalvik, r:Int, from:String, to:String) {
		inline function i(t:String)
			return t == "Z" || t == "B" || t == "C" || t == "S" || t == "I";
		if (from == to || (i(from) && i(to))) return;
		var op = if (i(from)) switch to {
			case "J": 0x81;
			case "F": 0x82;
			case _: 0x83;
		} else if (from == "J") to == "F" ? 0x85 : 0x86 else 0x89;
		// (through v2: a long's result over a narrow source)
		a.raw([op | 2 << 8 | r << 12]);
		move(a, r, 2, to);
	}
}

// one method's translation
private class Method {
	final host:Host;
	final m:JMethod;
	final c:ClassFile;
	final code:haxe.io.Bytes;
	final jcode:JCode;
	final insns:Array<Insn> = [];
	final index = new Map<Int, Int>();

	public function new(host:Host, m:JMethod) {
		this.host = host;
		this.m = m;
		c = host.c;
		jcode = m.code;
		code = jcode.code;
	}

	inline function s1(o:Int)
		return (code.get(o) << 24) >> 24;

	inline function u1(o:Int)
		return code.get(o);

	inline function u2(o:Int)
		return code.get(o) << 8 | code.get(o + 1);

	inline function s2(o:Int)
		return (u2(o) << 16) >> 16;

	inline function s4(o:Int)
		return code.get(o) << 24 | code.get(o + 1) << 16 | code.get(o + 2) << 8 | code.get(o + 3);

	function decode() {
		var pc = 0, n = code.length;
		while (pc < n) {
			var op = u1(pc), i:Insn = {pc: pc, op: op, len: 1, a: 0, b: 0};
			switch op {
				case 0x10:
					i.a = s1(pc + 1);
					i.len = 2;
				case 0x11:
					i.a = s2(pc + 1);
					i.len = 3;
				case 0x12:
					i.a = u1(pc + 1);
					i.len = 2;
				case 0x13 | 0x14:
					i.a = u2(pc + 1);
					i.len = 3;
				case 0x15 | 0x16 | 0x17 | 0x18 | 0x19 | 0x36 | 0x37 | 0x38 | 0x39 | 0x3a | 0xa9:
					i.a = u1(pc + 1);
					i.len = 2;
				case o if (o >= 0x1a && o <= 0x2d):
					i.op = 0x15 + Std.int((o - 0x1a) / 4);
					i.a = (o - 0x1a) % 4;
				case o if (o >= 0x3b && o <= 0x4e):
					i.op = 0x36 + Std.int((o - 0x3b) / 4);
					i.a = (o - 0x3b) % 4;
				case 0x84:
					i.a = u1(pc + 1);
					i.b = s1(pc + 2);
					i.len = 3;
				case o if (o >= 0x99 && o <= 0xa8 || o == 0xc6 || o == 0xc7):
					i.a = pc + s2(pc + 1);
					i.len = 3;
				case 0xc8 | 0xc9:
					i.op = op == 0xc8 ? 0xa7 : 0xa8;
					i.a = pc + s4(pc + 1);
					i.len = 5;
				case 0xaa:
					var at = (pc + 4) & ~3;
					var dflt = pc + s4(at), low = s4(at + 4), high = s4(at + 8);
					i.dflt = dflt;
					i.keys = [for (k in low...high + 1) k];
					i.targets = [for (k in 0...high - low + 1) pc + s4(at + 12 + 4 * k)];
					i.len = at + 12 + 4 * (high - low + 1) - pc;
				case 0xab:
					var at = (pc + 4) & ~3;
					var dflt = pc + s4(at), np = s4(at + 4);
					i.dflt = dflt;
					i.keys = [for (k in 0...np) s4(at + 8 + 8 * k)];
					i.targets = [for (k in 0...np) pc + s4(at + 12 + 8 * k)];
					i.len = at + 8 + 8 * np - pc;
				case o if (o >= 0xb2 && o <= 0xb8 || o == 0xbb || o == 0xbd || o == 0xc0 || o == 0xc1):
					i.a = u2(pc + 1);
					i.len = 3;
				case 0xb9 | 0xba:
					i.a = u2(pc + 1);
					i.len = 5;
				case 0xbc:
					i.a = u1(pc + 1);
					i.len = 2;
				case 0xc5:
					i.a = u2(pc + 1);
					i.b = u1(pc + 3);
					i.len = 4;
				case 0xc4:
					var w = u1(pc + 1);
					i.op = w;
					i.a = u2(pc + 2);
					i.len = 4;
					if (w == 0x84) {
						i.b = s2(pc + 4);
						i.len = 6;
					}
				case _:
			}
			index.set(pc, insns.length);
			insns.push(i);
			pc += i.len;
		}
	}

	// ---- types

	function initial():State {
		var locals = [for (_ in 0...jcode.maxLocals) "X"], k = 0;
		if (m.access & ClassFile.STATIC == 0) locals[k++] = m.name == "<init>" && c.name != "java/lang/Object" ? "T" : Jvm.desc(c.name);
		for (p in Jvm.signature(m.desc).params) {
			var t = Jvm.stackType(p);
			locals[k++] = t;
			if (Jvm.wide(t)) locals[k++] = "-";
		}
		return {locals: locals, stack: []};
	}

	function frameState(f:{pc:Int, locals:Null<Array<String>>, stack:Array<String>}):State {
		var locals = [];
		for (t in f.locals ?? []) {
			locals.push(t);
			if (Jvm.wide(t)) locals.push("-");
		}
		while (locals.length < jcode.maxLocals)
			locals.push("X");
		var stack = [];
		for (t in f.stack) {
			stack.push(t);
			if (Jvm.wide(t)) stack.push("-");
		}
		return {locals: locals, stack: stack};
	}

	var newTypes = new Map<Int, String>();

	function constType(k:JConst):String
		return switch k {
			case CInt(_): "I";
			case CFloat(_): "F";
			case CLong(_, _): "J";
			case CDouble(_, _): "D";
			case CString(_): "Ljava/lang/String;";
			case CClass(_): "Ljava/lang/Class;";
			case CMethodType(_): "Ljava/lang/invoke/MethodType;";
			case CHandle(_): "Ljava/lang/invoke/MethodHandle;";
			case CDynamic(_, _, d): Jvm.stackType(d);
		}

	static final PRIMS = [4 => "Z", 5 => "C", 6 => "F", 7 => "D", 8 => "B", 9 => "S", 10 => "I", 11 => "J"];
	static final WRAPPERS = [
		"Z" => "Boolean", "B" => "Byte", "C" => "Character", "S" => "Short", "I" => "Integer", "J" => "Long", "F" => "Float", "D" => "Double"
	];

	// the state after an instruction (its successors' before)
	function step(i:Insn, s:State):State {
		var locals = s.locals.copy(), stack = s.stack.copy();
		inline function pop(n:Int)
			stack.splice(stack.length - n, n);
		function push(t:String) {
			stack.push(t);
			if (Jvm.wide(t)) stack.push("-");
		}
		function popType(t:String)
			pop(Jvm.wide(t) ? 2 : 1);
		var op = i.op;
		switch op {
			case 0x00:
			case 0x01: push("N");
			case o if (o >= 0x02 && o <= 0x08): push("I");
			case 0x09 | 0x0a: push("J");
			case 0x0b | 0x0c | 0x0d: push("F");
			case 0x0e | 0x0f: push("D");
			case 0x10 | 0x11: push("I");
			case 0x12 | 0x13 | 0x14: push(constType(c.pool.value(i.a)));
			case o if (o >= 0x15 && o <= 0x19): push(locals[i.a]);
			case o if (o >= 0x2e && o <= 0x35):
				var arr = stack[stack.length - 2];
				pop(2);
				push(switch o {
					case 0x2f: "J";
					case 0x30: "F";
					case 0x31: "D";
					case 0x32: arr.charAt(0) == "[" ? arr.substr(1) : "R";
					case _: "I";
				});
			case o if (o >= 0x36 && o <= 0x3a):
				var t = stack[stack.length - 1] == "-" ? stack[stack.length - 2] : stack[stack.length - 1];
				popType(t);
				if (i.a > 0 && Jvm.wide(locals[i.a - 1])) locals[i.a - 1] = "X";
				if (locals[i.a + 1] == "-" && !Jvm.wide(t)) locals[i.a + 1] = "X";
				locals[i.a] = t;
				if (Jvm.wide(t)) locals[i.a + 1] = "-";
			case o if (o >= 0x4f && o <= 0x56): pop(o == 0x50 || o == 0x52 ? 4 : 3);
			case 0x57: pop(1);
			case 0x58: pop(2);
			case 0x59: stack.push(stack[stack.length - 1]);
			case o if (o >= 0x5a && o <= 0x5f):
				var n = stack.length;
				var w = [for (k in 0...4) n - 1 - k >= 0 ? stack[n - 1 - k] : null];
				// (w[0] the top word)
				switch o {
					case 0x5a: stack.splice(n - 2, 2).length; stack.push(w[0]); stack.push(w[1]); stack.push(w[0]);
					case 0x5b: stack.splice(n - 3, 3); stack.push(w[0]); stack.push(w[2]); stack.push(w[1]); stack.push(w[0]);
					case 0x5c: stack.push(w[1]); stack.push(w[0]);
					case 0x5d: stack.splice(n - 3, 3); for (x in [w[1], w[0], w[2], w[1], w[0]]) stack.push(x);
					case 0x5e: stack.splice(n - 4, 4); for (x in [w[1], w[0], w[3], w[2], w[1], w[0]]) stack.push(x);
					case _: stack.splice(n - 2, 2); stack.push(w[0]); stack.push(w[1]);
				}
			case o if (o >= 0x60 && o <= 0x77):
				var t = ["I", "J", "F", "D"][(o - 0x60) % 4];
				popType(t);
				if (o < 0x74) popType(t);
				push(t);
			case o if (o >= 0x78 && o <= 0x7d):
				var t = (o - 0x78) % 2 == 0 ? "I" : "J";
				pop(1);
				popType(t);
				push(t);
			case o if (o >= 0x7e && o <= 0x83):
				var t = (o - 0x7e) % 2 == 0 ? "I" : "J";
				popType(t);
				popType(t);
				push(t);
			case 0x84:
			case o if (o >= 0x85 && o <= 0x93):
				var from = ["I", "I", "I", "J", "J", "J", "F", "F", "F", "D", "D", "D", "I", "I", "I"][o - 0x85];
				var to = ["J", "F", "D", "I", "F", "D", "I", "J", "D", "I", "J", "F", "I", "I", "I"][o - 0x85];
				popType(from);
				push(to);
			case 0x94: pop(4); push("I");
			case 0x95 | 0x96: pop(2); push("I");
			case 0x97 | 0x98: pop(4); push("I");
			case o if (o >= 0x99 && o <= 0x9e): pop(1);
			case o if (o >= 0x9f && o <= 0xa6): pop(2);
			case 0xa7:
			case 0xa8 | 0xa9: throw "jsr and ret";
			case 0xaa | 0xab: pop(1);
			case 0xac | 0xae | 0xb0: pop(1);
			case 0xad | 0xaf: pop(2);
			case 0xb1:
			case 0xb2: push(Jvm.stackType(c.pool.ref(i.a).desc));
			case 0xb3: popType(c.pool.ref(i.a).desc);
			case 0xb4:
				pop(1);
				push(Jvm.stackType(c.pool.ref(i.a).desc));
			case 0xb5:
				popType(c.pool.ref(i.a).desc);
				pop(1);
			case o if (o >= 0xb6 && o <= 0xb9):
				var r = c.pool.ref(i.a), sig = Jvm.signature(r.desc);
				var n = 0;
				for (p in sig.params)
					n += Jvm.wide(p) ? 2 : 1;
				pop(n);
				if (o != 0xb8) {
					var recv = stack.pop();
					if (o == 0xb7 && r.name == "<init>" && (recv == "T" || recv.charAt(0) == "U")) {
						var t = recv == "T" ? Jvm.desc(c.name) : newTypes.get(Std.parseInt(recv.substr(1)));
						for (k in 0...locals.length) if (locals[k] == recv) locals[k] = t;
						for (k in 0...stack.length) if (stack[k] == recv) stack[k] = t;
					}
				}
				if (sig.ret != "V") push(Jvm.stackType(sig.ret));
			case 0xba:
				var sig = Jvm.signature(indyDesc(i)), n = 0;
				for (p in sig.params)
					n += Jvm.wide(p) ? 2 : 1;
				pop(n);
				if (sig.ret != "V") push(Jvm.stackType(sig.ret));
			case 0xbb:
				newTypes.set(i.pc, Jvm.desc(c.pool.cls(i.a)));
				push("U" + i.pc);
			case 0xbc:
				pop(1);
				push("[" + PRIMS.get(i.a));
			case 0xbd:
				pop(1);
				push("[" + Jvm.desc(c.pool.cls(i.a)));
			case 0xbe:
				pop(1);
				push("I");
			case 0xbf: pop(1);
			case 0xc0:
				pop(1);
				push(Jvm.desc(c.pool.cls(i.a)));
			case 0xc1:
				pop(1);
				push("I");
			case 0xc2 | 0xc3: pop(1);
			case 0xc5:
				pop(i.b);
				push(Jvm.desc(c.pool.cls(i.a)));
			case 0xc6 | 0xc7: pop(1);
			case o: throw 'opcode 0x${StringTools.hex(o, 2)}';
		}
		return {locals: locals, stack: stack};
	}

	inline function u2Pool(o:Int):Int
		return c.pool.u2(o);

	// where control goes after i: [next, targets...]
	static function falls(i:Insn):Bool
		return switch i.op {
			case 0xa7 | 0xaa | 0xab | 0xac | 0xad | 0xae | 0xaf | 0xb0 | 0xb1 | 0xbf | 0xa9: false;
			case _: true;
		}

	static function targets(i:Insn):Array<Int>
		return switch i.op {
			case o if (o >= 0x99 && o <= 0xa7 || o == 0xc6 || o == 0xc7): [i.a];
			case 0xaa | 0xab: [i.dflt].concat(i.targets);
			case _: [];
		}

	var states:Array<Null<State>>;

	function infer() {
		states = [for (_ in 0...insns.length) null];
		var frames = new Map<Int, State>();
		if (jcode.frames != null) for (f in jcode.frames)
			frames.set(f.pc, frameState(f));
		var work = [0];
		states[0] = initial();
		function into(pc:Int, s:State) {
			var k = index.get(pc);
			if (k == null) throw 'a branch to $pc';
			var cur = states[k];
			if (cur == null) {
				var f = frames.get(pc);
				states[k] = f ?? {locals: s.locals.copy(), stack: s.stack.copy()};
				work.push(k);
				return;
			}
			if (frames.exists(pc)) return;
			if (cur.stack.length != s.stack.length) throw 'stack heights differ at $pc';
			var changed = false;
			for (j in 0...cur.locals.length) {
				var t = Jvm.merge(cur.locals[j], s.locals[j]);
				if (t != cur.locals[j]) {
					cur.locals[j] = t;
					changed = true;
				}
			}
			for (j in 0...cur.stack.length) {
				var t = Jvm.merge(cur.stack[j], s.stack[j]);
				if (t != cur.stack[j]) {
					cur.stack[j] = t;
					changed = true;
				}
			}
			if (changed) work.push(k);
		}
		while (work.length > 0) {
			var k = work.pop(), i = insns[k], s = states[k];
			var after = step(i, s);
			for (h in jcode.handlers)
				if (i.pc >= h.start && i.pc < h.end) {
					var ex = [h.type == null ? "Ljava/lang/Throwable;" : Jvm.desc(h.type)];
					into(h.handler, {locals: s.locals, stack: ex});
					if (i.op >= 0x36 && i.op <= 0x3a || i.op == 0x84) into(h.handler, {locals: after.locals, stack: ex});
				}
			if (falls(i) && k + 1 < insns.length) into(insns[k + 1].pc, after);
			for (t in targets(i))
				into(t, after);
		}
	}

	// ---- code

	var asm:Dalvik;
	var labels:Map<Int, Int>;
	var stk:Array<Int>;
	var typ:Array<String>;
	// an int constant not yet in its word's register (a literal for the instruction that takes it)
	var kon:Array<Null<Int>> = [];
	var base:Int;
	var maxStack:Int;
	var extra:Int;
	var argWords:Int;
	var straddle:Bool;
	// each local's register past the stack's and temporaries' (Method.number)
	var regOf:Array<Int> = [];
	var lock = -1;
	var scratchN = 0;
	var outs = 0;
	var skip:Array<Bool>;
	var blockStart:Array<Bool>;

	function lab(pc:Int):Int {
		var l = labels.get(pc);
		if (l == null) labels.set(pc, l = asm.label());
		return l;
	}

	inline function canon(w:Int):Int
		return base + w;

	inline function tmp(k:Int):Int
		return base + maxStack + k;

	function lreg(i:Int):Int {
		var at = base + maxStack + extra;
		return at + regOf[i];
	}

	static function kind(t:String):Int
		return switch t {
			case "J" | "D": 2;
			case "-": 3;
			case "I" | "F" | "Z" | "B" | "C" | "S": 0;
			case _: 1;
		}

	function move(dst:Int, src:Int, t:String) {
		if (dst == src) return;
		var k = kind(t), op = k == 2 ? 0x04 : k == 1 ? 0x07 : 0x01;
		if (dst < 16 && src < 16) asm.raw([op | dst << 8 | src << 12]) else if (dst < 256) asm.raw([op + 1 | dst << 8, src]) else
			asm.raw([op + 2, dst, src]);
	}

	// a constant word's value written to its register
	function realize(w:Int) {
		var v = kon[w];
		if (v == null) return;
		kon[w] = null;
		konst(stk[w], v);
	}

	function materialize(from:Int) {
		for (w in from...stk.length)
			realize(w);
		var w = from;
		while (w < stk.length) {
			var t = typ[w];
			if (t == "-") {
				w++;
				continue;
			}
			var cw = canon(w);
			if (stk[w] != cw) {
				move(cw, stk[w], t);
				stk[w] = cw;
				if (kind(t) == 2) stk[w + 1] = cw + 1;
			}
			w += kind(t) == 2 ? 2 : 1;
		}
	}

	// the stack's words that read regs, moved to their own registers first
	function clobber(regs:Array<Int>) {
		var w = 0;
		while (w < stk.length) {
			var t = typ[w];
			if (t == "-") {
				w++;
				continue;
			}
			var wd = kind(t) == 2, r = stk[w];
			if (r != canon(w) && (regs.indexOf(r) >= 0 || (wd && regs.indexOf(r + 1) >= 0))) {
				move(canon(w), r, t);
				stk[w] = canon(w);
				if (wd) stk[w + 1] = canon(w) + 1;
			}
			w += wd ? 2 : 1;
		}
	}

	// word w's register within bits (moved to its own register, else to scratch at s)
	function use(w:Int, bits:Int, s:Int):Int {
		realize(w);
		var r = stk[w], limit = 1 << bits;
		if (r < limit) return r;
		var cw = canon(w);
		if (cw < limit) {
			move(cw, r, typ[w]);
			stk[w] = cw;
			if (kind(typ[w]) == 2) stk[w + 1] = cw + 1;
			return cw;
		}
		if (s + (kind(typ[w]) == 2 ? 2 : 1) > scratchN) throw "no scratch register";
		move(s, r, typ[w]);
		return s;
	}

	function drop(n:Int) {
		stk.splice(stk.length - n, n);
		typ.splice(typ.length - n, n);
		kon.splice(kon.length - n, n);
	}

	function push(r:Int, t:String) {
		stk.push(r);
		typ.push(t);
		kon.push(null);
		if (kind(t) == 2) {
			stk.push(r + 1);
			typ.push("-");
			kon.push(null);
		}
	}

	function word(r:Int, t:String, k:Null<Int>) {
		stk.push(r);
		typ.push(t);
		kon.push(k);
	}

	var forward = -1;

	// where a result of type t lands (word w): a local the next instruction
	// stores it to (store: that instruction's index), its own register, or
	// scratch v0 when that is out of the instruction's bits
	function dest(w:Int, t:String, bits:Int, store:Int):Int {
		forward = -1;
		// (a cast then a store: the result in the local, the cast on it there, when no handler sees the local between)
		if (store >= 0 && store + 1 < insns.length && insns[store].op == 0xc0 && insns[store + 1].op == 0x3a && !blockStart[store]
			&& !blockStart[store + 1] && states[store + 1] != null && store != current) {
			var r = lreg(insns[store + 1].a), pc = insns[store].pc, covered = false;
			for (h in jcode.handlers)
				if (h.start <= pc && h.end > insns[current].pc) covered = true;
			if (!covered && r < 1 << bits) {
				clobber(kind(t) == 2 ? [r, r + 1] : [r]);
				return r;
			}
		}
		if (store >= 0 && store < insns.length && !skip[store] && states[store] != null && (!blockStart[store] || store == current)) {
			var n = insns[store];
			if (n.op >= 0x36 && n.op <= 0x3a) {
				var r = lreg(n.a);
				if (r < 1 << bits) {
					clobber(kind(t) == 2 ? [r, r + 1] : [r]);
					forward = store;
					skip[store] = true;
					return r;
				}
			}
		}
		var cw = canon(w);
		if (cw < 1 << bits) return cw;
		return 0;
	}

	// the result in r: pushed (moved to its register from scratch, or a
	// local's that a cast then stores to), or stored
	function result(w:Int, r:Int, t:String) {
		if (forward >= 0) {
			forward = -1;
			return;
		}
		var cw = canon(w);
		if (r >= base + maxStack + extra) {
			push(r, t);
			return;
		}
		if (r != cw) move(cw, r, t);
		push(cw, t);
	}

	var current = 0;

	static function fieldOp(t:String):Int
		return switch t.charAt(0) {
			case "J" | "D": 1;
			case "L" | "[": 2;
			case "Z": 3;
			case "B": 4;
			case "C": 5;
			case "S": 6;
			case _: 0;
		}

	function konst(r:Int, v:Int) {
		if (r < 16 && v >= -8 && v < 8) asm.raw([0x12 | r << 8 | (v & 0xf) << 12]) else if (v >= -32768 && v < 32768) asm.raw([0x13 | r << 8, v & 0xffff]) else
			if (v & 0xffff == 0) asm.raw([0x15 | r << 8, v >>> 16]) else asm.raw([0x14 | r << 8, v & 0xffff, v >>> 16]);
	}

	function konstWide(r:Int, hi:Int, lo:Int) {
		if (hi == lo >> 31 && lo >= -32768 && lo < 32768) asm.raw([0x16 | r << 8, lo & 0xffff]) else if (hi == lo >> 31)
			asm.raw([0x17 | r << 8, lo & 0xffff, lo >>> 16]) else if (lo == 0 && hi & 0xffff == 0) asm.raw([0x19 | r << 8, hi >>> 16]) else
			asm.raw([0x18 | r << 8, lo & 0xffff, lo >>> 16, hi & 0xffff, hi >>> 16]);
	}

	function wordsOf(params:Array<String>):Int {
		var n = 0;
		for (p in params)
			n += Jvm.wide(p) ? 2 : 1;
		return n;
	}

	// the registers of words from..top, as an invoke lists them (five or
	// fewer: those past v15 moved to their own registers when those are under it)
	function args(from:Int):Array<Int> {
		for (w in from...stk.length)
			realize(w);
		var regs = [for (w in from...stk.length) stk[w]];
		if (Dalvik.short(regs) || Dalvik.consecutive(regs)) return regs;
		if (regs.length <= 5 && canon(stk.length - 1) < 16) {
			var w = from;
			while (w < stk.length) {
				var t = typ[w];
				if (t != "-" && stk[w] + (kind(t) == 2 ? 1 : 0) > 15) {
					move(canon(w), stk[w], t);
					stk[w] = canon(w);
					if (kind(t) == 2) stk[w + 1] = canon(w) + 1;
				}
				w++;
			}
			return [for (w in from...stk.length) stk[w]];
		}
		materialize(from);
		return [for (w in from...stk.length) stk[w]];
	}

	// values (register, type) as one call's consecutive registers: copied to the temporaries from t0
	function block(values:Array<{r:Int, t:String}>, t0:Int):Array<Int> {
		var regs = [];
		for (v in values) {
			regs.push(v.r);
			if (Jvm.wide(v.t)) regs.push(v.r + 1);
		}
		if (Dalvik.short(regs) || Dalvik.consecutive(regs)) return regs;
		var at = t0;
		regs = [];
		for (v in values) {
			move(tmp(at), v.r, v.t);
			regs.push(tmp(at));
			if (Jvm.wide(v.t)) regs.push(tmp(at) + 1);
			at += Jvm.wide(v.t) ? 2 : 1;
		}
		return regs;
	}

	function call(op:Int, regs:Array<Int>, r:DRef) {
		if (regs.length > outs) outs = regs.length;
		asm.invoke(op, regs, r);
	}

	function resultOp(t:String):Int
		return kind(t) == 2 ? 0x0b : kind(t) == 1 ? 0x0c : 0x0a;

	public function translate():DexCode {
		decode();
		infer();
		asm = new Dalvik();
		labels = new Map();
		var n = insns.length;
		skip = [for (_ in 0...n) false];
		blockStart = [for (_ in 0...n) false];
		var jumped = [for (_ in 0...n) false];
		for (k in 0...n)
			if (states[k] != null) for (t in targets(insns[k]))
				jumped[index.get(t)] = true;
		for (k in 0...n)
			blockStart[k] = jumped[k];
		var handlerAt = new Map<Int, Bool>();
		for (h in jcode.handlers) {
			var k = index.get(h.handler);
			if (k != null && states[k] != null) {
				blockStart[k] = true;
				handlerAt.set(h.handler, true);
			}
		}
		// a handler entered also by code: its move-exception a stub's
		var stubs = new Map<Int, Int>();
		for (pc in handlerAt.keys()) {
			var k = index.get(pc);
			if (jumped[k] || (k > 0 && states[k - 1] != null && falls(insns[k - 1]))) stubs.set(pc, -1);
		}
		maxStack = jcode.maxStack;
		argWords = (m.access & ClassFile.STATIC == 0 ? 1 : 0) + wordsOf(Jvm.signature(m.desc).params);
		extra = 0;
		straddle = false;
		var sync = m.access & ClassFile.SYNCHRONIZED != 0;
		for (k in 0...n) {
			var i = insns[k];
			if (states[k] == null) continue;
			switch i.op {
				case o if (o >= 0x5a && o <= 0x5f): if (extra < 4) extra = 4;
				case 0xc5: if (extra < 2) extra = 2;
				case 0xba:
					var b = indy(i);
					var need = 3;
					if (b.method.owner == "java/lang/invoke/LambdaMetafactory") need = 1 + wordsOf(Jvm.signature(indyDesc(i)).params);
					if (extra < need) extra = need;
				case o if ((o == 0x16 || o == 0x18 || o == 0x37 || o == 0x39) && i.a == argWords - 1): straddle = true;
				case _:
			}
		}
		if (sync && maxStack < 1) maxStack = 1;
		var scratch = (sync ? 1 : 0) + maxStack + extra > 16 ? 4 : 0;
		number((sync ? 1 : 0) + scratch + maxStack + extra);
		base = scratch + (sync ? 1 : 0);
		scratchN = scratch;
		if (sync) lock = scratch;
		var total = base + maxStack + extra + jcode.maxLocals + (straddle ? argWords : 0);
		if (total > 65535) throw "too many registers";
		// the prologue: the arguments to their locals (straddle), the lock
		if (straddle) {
			var at = total - argWords, k = 0;
			var init = initial();
			while (k < argWords) {
				var t = init.locals[k];
				move(lreg(k), at + k, t);
				k += Jvm.wide(t) ? 2 : 1;
			}
		}
		if (sync) {
			if (m.access & ClassFile.STATIC != 0) asm.ref(0x1c, lock, RType(Jvm.desc(c.name))) else move(lock, lreg(0), "L");
			asm.raw([0x1d | lock << 8]);
		}
		stk = [];
		typ = [];
		kon = [];
		var prevFalls = true;
		for (k in 0...n) {
			var i = insns[k];
			current = k;
			var s = states[k];
			if (s == null) {
				asm.place(lab(i.pc));
				prevFalls = false;
				continue;
			}
			if (blockStart[k]) {
				if (prevFalls) materialize(0);
				stk = [for (w in 0...s.stack.length) canon(w)];
				kon = [for (_ in 0...s.stack.length) null];
			}
			asm.place(lab(i.pc));
			if (handlerAt.exists(i.pc) && !stubs.exists(i.pc)) {
				typ = s.stack.copy();
				drop(1);
				var r = dest(0, s.stack[0], 8, k);
				asm.raw([0x0d | r << 8]);
				result(0, r, s.stack[0]);
			}
			if (skip[k]) {
				prevFalls = falls(i);
				continue;
			}
			if (stk.length != s.stack.length) throw 'stack height at ${i.pc}';
			typ = s.stack.copy();
			emit(i, k, s);
			prevFalls = falls(i);
		}
		asm.place(lab(code.length));
		// the stubs, the lock's handler
		for (pc in [for (p in stubs.keys()) p]) {
			var l = asm.label();
			stubs.set(pc, l);
			asm.place(l);
			asm.raw([0x0d | canon(0) << 8]);
			asm.goto(lab(pc));
		}
		var syncLabel = -1;
		if (sync) {
			syncLabel = asm.label();
			asm.place(syncLabel);
			asm.raw([0x0d | canon(0) << 8]);
			asm.raw([0x1e | lock << 8]);
			asm.raw([0x27 | canon(0) << 8]);
		}
		// the try items: between each pair of the ranges' bounds, the handlers covering it
		var entries = [for (h in jcode.handlers) if (states[index.get(h.handler)] != null) {
			start: h.start,
			end: h.end,
			label: stubs.exists(h.handler) ? stubs.get(h.handler) : lab(h.handler),
			type: h.type
		}];
		if (sync) entries.push({start: 0, end: code.length, label: syncLabel, type: null});
		var bounds = [];
		for (e in entries)
			for (b in [e.start, e.end])
				if (bounds.indexOf(b) < 0) bounds.push(b);
		bounds.sort((a, b) -> a - b);
		var tries = [];
		for (j in 0...bounds.length - 1) {
			var lo = bounds[j], hs = [], all:Null<Int> = null, seen = new Map<String, Bool>();
			for (e in entries)
				if (e.start <= lo && lo < e.end) {
					if (e.type == null) {
						all = e.label;
						break;
					}
					var d = Jvm.desc(e.type);
					if (seen.exists(d)) continue;
					seen.set(d, true);
					hs.push({type: d, label: e.label});
				}
			if (hs.length == 0 && all == null) continue;
			tries.push({start: lab(lo), end: lab(bounds[j + 1]), handlers: hs, all: all});
		}
		return asm.code(total, argWords, outs, tries);
	}

	function indy(i:Insn):{method:JHandle, args:Array<JConst>} {
		var o = c.pool.at[i.a];
		return c.bootstraps[u2Pool(o)];
	}

	function indyNameType(i:Insn):{name:String, desc:String} {
		var o = c.pool.at[i.a], nt = c.pool.at[u2Pool(o + 2)];
		return {name: c.pool.utf8(u2Pool(nt)), desc: c.pool.utf8(u2Pool(nt + 2))};
	}

	function indyDesc(i:Insn):String
		return indyNameType(i).desc;

	var lambdaCount = 0;

	function emit(i:Insn, k:Int, s:State) {
		var op = i.op, depth = stk.length;
		switch op {
			case 0x00:
			case 0x01:
				var r = dest(depth, "N", 8, k + 1);
				konst(r, 0);
				result(depth, r, "N");
			case 0x02 | 0x03 | 0x04 | 0x05 | 0x06 | 0x07 | 0x08 | 0x10 | 0x11:
				word(canon(depth), "I", op <= 0x08 ? op - 0x03 : i.a);
			case 0x09 | 0x0a:
				var r = dest(depth, "J", 8, k + 1);
				konstWide(r, 0, op - 0x09);
				result(depth, r, "J");
			case 0x0b | 0x0c | 0x0d:
				var r = dest(depth, "F", 8, k + 1);
				konst(r, [0, 0x3f800000, 0x40000000][op - 0x0b]);
				result(depth, r, "F");
			case 0x0e | 0x0f:
				var r = dest(depth, "D", 8, k + 1);
				konstWide(r, op == 0x0e ? 0 : 0x3ff00000, 0);
				result(depth, r, "D");
			case 0x12 | 0x13 | 0x14:
				var v = c.pool.value(i.a), t = constType(v);
				switch v {
					case CInt(x):
						word(canon(depth), "I", x);
					case CFloat(x):
						var r = dest(depth, t, 8, k + 1);
						konst(r, x);
						result(depth, r, t);
					case CLong(hi, lo) | CDouble(hi, lo):
						var r = dest(depth, t, 8, k + 1);
						konstWide(r, hi, lo);
						result(depth, r, t);
					case CString(str):
						var r = dest(depth, t, 8, k + 1);
						asm.string(r, str);
						result(depth, r, t);
					case CClass(name):
						var r = dest(depth, t, 8, k + 1);
						asm.ref(0x1c, r, RType(Jvm.desc(name)));
						result(depth, r, t);
					case _: throw "ldc of a method handle, type or dynamic constant";
				}
			case o if (o >= 0x15 && o <= 0x19):
				var t = s.locals[i.a];
				if (t == "X" || t == "-") throw 'a load of an unset local at ${i.pc}';
				push(lreg(i.a), t);
			case o if (o >= 0x2e && o <= 0x35):
				var idx = use(depth - 1, 8, 2), arr = use(depth - 2, 8, 0);
				var arrT = typ[depth - 2];
				drop(2);
				var t = switch o {
					case 0x2f: "J";
					case 0x30: "F";
					case 0x31: "D";
					case 0x32: arrT.charAt(0) == "[" ? arrT.substr(1) : "R";
					case _: "I";
				};
				var dop = switch o {
					case 0x2e | 0x30: 0x44;
					case 0x2f | 0x31: 0x45;
					case 0x32: 0x46;
					case 0x33: arrT == "[Z" ? 0x47 : 0x48;
					case 0x34: 0x49;
					case _: 0x4a;
				};
				var r = dest(depth - 2, t, 8, k + 1);
				asm.raw([dop | r << 8, arr | idx << 8]);
				result(depth - 2, r, t);
			case o if (o >= 0x36 && o <= 0x3a):
				var wd = o == 0x37 || o == 0x39, nw = wd ? 2 : 1, t = typ[depth - nw];
				var r = lreg(i.a), kv = kon[depth - nw];
				if (kv != null && r < 256) {
					drop(nw);
					clobber([r]);
					konst(r, kv);
					return;
				}
				realize(depth - nw);
				var v = stk[depth - nw];
				drop(nw);
				clobber(wd ? [r, r + 1] : [r]);
				move(r, v, t);
			case o if (o >= 0x4f && o <= 0x56):
				var wd = o == 0x50 || o == 0x52, nw = wd ? 2 : 1;
				var v = use(depth - nw, 8, 0), idx = use(depth - nw - 1, 8, 2), arr = use(depth - nw - 2, 8, 3);
				var arrT = typ[depth - nw - 2];
				drop(nw + 2);
				var dop = switch o {
					case 0x4f | 0x51: 0x4b;
					case 0x50 | 0x52: 0x4c;
					case 0x53: 0x4d;
					case 0x54: arrT == "[Z" ? 0x4e : 0x4f;
					case 0x55: 0x50;
					case _: 0x51;
				};
				asm.raw([dop | v << 8, arr | idx << 8]);
			case 0x57: drop(1);
			case 0x58: drop(2);
			case 0x59:
				if (kon[depth - 1] != null) word(canon(depth), "I", kon[depth - 1]) else push(stk[depth - 1], typ[depth - 1]);
			case 0x5c:
				realize(depth - 2);
				realize(depth - 1);
				var r1 = stk[depth - 2], t1 = typ[depth - 2], r0 = stk[depth - 1], t0 = typ[depth - 1];
				word(r1, t1, null);
				word(r0, t0, null);
			case o if (o >= 0x5a && o <= 0x5f):
				permute(o, depth);
			case o if (o >= 0x60 && o <= 0x73 || o >= 0x78 && o <= 0x83):
				var t:String, dop:Int, bw:Int, cw:Int;
				if (o <= 0x73) {
					t = ["I", "J", "F", "D"][(o - 0x60) % 4];
					var g = Std.int((o - 0x60) / 4);
					dop = [0x90, 0x9b, 0xa6, 0xab][(o - 0x60) % 4] + g;
					bw = cw = Jvm.wide(t) ? 2 : 1;
				} else if (o <= 0x7d) {
					t = (o - 0x78) % 2 == 0 ? "I" : "J";
					dop = [0x98, 0xa3, 0x99, 0xa4, 0x9a, 0xa5][o - 0x78];
					bw = Jvm.wide(t) ? 2 : 1;
					cw = 1;
				} else {
					t = (o - 0x7e) % 2 == 0 ? "I" : "J";
					dop = [0x95, 0xa0, 0x96, 0xa1, 0x97, 0xa2][o - 0x7e];
					bw = cw = Jvm.wide(t) ? 2 : 1;
				}
				var d = depth - bw - cw;
				if (t == "I" && literal(o, d, k)) return;
				var b = use(d, 8, 0), cr = use(d + bw, 8, 2);
				drop(bw + cw);
				var r = dest(d, t, 8, k + 1);
				if (r == b && r < 16 && cr < 16) asm.raw([dop + 0x20 | r << 8 | cr << 12]) else asm.raw([dop | r << 8, b | cr << 8]);
				result(d, r, t);
			case o if (o >= 0x74 && o <= 0x77):
				var t = ["I", "J", "F", "D"][o - 0x74], nw = Jvm.wide(t) ? 2 : 1;
				var b = use(depth - nw, 4, 0);
				drop(nw);
				var r = dest(depth - nw, t, 4, k + 1);
				asm.raw([[0x7b, 0x7d, 0x7f, 0x80][o - 0x74] | r << 8 | b << 12]);
				result(depth - nw, r, t);
			case 0x84:
				var r = lreg(i.a);
				clobber([r]);
				if (i.b >= -128 && i.b < 128 && r < 256) asm.raw([0xd8 | r << 8, r | (i.b & 0xff) << 8]) else if (r < 16)
					asm.raw([0xd0 | r << 8 | r << 12, i.b & 0xffff]) else {
					konst(0, i.b);
					if (r >= 256) throw "iinc of a local past v255";
					asm.raw([0x90 | r << 8, r | 0 << 8]);
				}
			case o if (o >= 0x85 && o <= 0x93):
				var from = ["I", "I", "I", "J", "J", "J", "F", "F", "F", "D", "D", "D", "I", "I", "I"][o - 0x85];
				var to = ["J", "F", "D", "I", "F", "D", "I", "J", "D", "I", "J", "F", "I", "I", "I"][o - 0x85];
				var nw = Jvm.wide(from) ? 2 : 1;
				var b = use(depth - nw, 4, 0);
				drop(nw);
				var r = dest(depth - nw, to, 4, k + 1);
				asm.raw([(o - 4) | r << 8 | b << 12]);
				result(depth - nw, r, to);
			case o if (o >= 0x94 && o <= 0x98):
				var nw = o == 0x95 || o == 0x96 ? 1 : 2;
				var d = depth - 2 * nw;
				var b = use(d, 8, 0), cr = use(d + nw, 8, 2);
				drop(2 * nw);
				var r = dest(d, "I", 8, k + 1);
				asm.raw([[0x31, 0x2d, 0x2e, 0x2f, 0x30][o - 0x94] | r << 8, b | cr << 8]);
				result(d, r, "I");
			case o if (o >= 0x99 && o <= 0x9e || o == 0xc6 || o == 0xc7):
				var r = use(depth - 1, 8, 0);
				drop(1);
				materialize(0);
				asm.branch(o == 0xc6 ? 0x38 : o == 0xc7 ? 0x39 : o - 0x61, r, -1, lab(i.a));
			case o if (o >= 0x9f && o <= 0xa4 && (kon[depth - 1] == 0 || kon[depth - 2] == 0)):
				// (against a constant 0: the z form, the test turned when the 0 is first)
				var first = kon[depth - 1] == 0, x = use(first ? depth - 2 : depth - 1, 8, 0);
				drop(2);
				materialize(0);
				asm.branch(first ? o - 0x67 : [0x38, 0x39, 0x3c, 0x3d, 0x3a, 0x3b][o - 0x9f], x, -1, lab(i.a));
			case o if (o >= 0x9f && o <= 0xa6):
				var a = use(depth - 2, 4, 0), b = use(depth - 1, 4, 2);
				drop(2);
				materialize(0);
				asm.branch(o >= 0xa5 ? o - 0x73 : o - 0x6d, a, b, lab(i.a));
			case 0xa7:
				materialize(0);
				asm.goto(lab(i.a));
			case 0xaa | 0xab:
				var r = use(depth - 1, 8, 0);
				drop(1);
				materialize(0);
				asm.switchOf(r, i.keys, [for (t in i.targets) lab(t)]);
				asm.goto(lab(i.dflt));
			case o if (o >= 0xac && o <= 0xb1):
				if (o == 0xb1) {
					if (lock >= 0) asm.raw([0x1e | lock << 8]);
					asm.raw([0x0e]);
				} else {
					var nw = o == 0xad || o == 0xaf ? 2 : 1;
					var r = use(depth - nw, 8, 0);
					if (lock >= 0) asm.raw([0x1e | lock << 8]);
					asm.raw([(o == 0xb0 ? 0x11 : nw == 2 ? 0x10 : 0x0f) | r << 8]);
				}
			case 0xb2 | 0xb3 | 0xb4 | 0xb5:
				var f = c.pool.ref(i.a), t = Jvm.stackType(f.desc), nw = Jvm.wide(t) ? 2 : 1;
				var ref = RField(Jvm.desc(f.owner), f.name, f.desc), fo = fieldOp(f.desc);
				switch op {
					case 0xb2:
						var r = dest(depth, t, 8, k + 1);
						asm.ref(0x60 + fo, r, ref);
						result(depth, r, t);
					case 0xb3:
						var v = use(depth - nw, 8, 0);
						drop(nw);
						asm.ref(0x67 + fo, v, ref);
					case 0xb4:
						var obj = use(depth - 1, 4, 0);
						drop(1);
						var r = dest(depth - 1, t, 4, k + 1);
						asm.ref(0x52 + fo, r | obj << 4, ref);
						result(depth - 1, r, t);
					case _:
						var v = use(depth - nw, 4, 0), obj = use(depth - nw - 1, 4, 2);
						drop(nw + 1);
						asm.ref(0x59 + fo, v | obj << 4, ref);
				}
			case o if (o >= 0xb6 && o <= 0xb9):
				var r = c.pool.ref(i.a), sig = Jvm.signature(r.desc);
				var nw = wordsOf(sig.params) + (o == 0xb8 ? 0 : 1), d = depth - nw;
				var regs = args(d);
				var statified = o != 0xb8 && host.jvm.relaxedOf(r.owner, r.name, r.desc) == true;
				var dop = switch o {
					case _ if (statified): Dalvik.INVOKE_STATIC;
					case 0xb8: Dalvik.INVOKE_STATIC;
					case 0xb7:
						r.name == "<init>" || (r.owner == c.name && isPrivate(r)) ? Dalvik.INVOKE_DIRECT : Dalvik.INVOKE_SUPER;
					case 0xb9: isPrivate(r) ? Dalvik.INVOKE_DIRECT : Dalvik.INVOKE_INTERFACE;
					case _: isPrivate(r) ? Dalvik.INVOKE_DIRECT : Dalvik.INVOKE_VIRTUAL;
				};
				var params = statified ? [Jvm.desc(r.owner)].concat(sig.params) : sig.params;
				drop(nw);
				var ret = Jvm.stackType(sig.ret), dst = -1;
				var popped = false;
				if (ret != "V") {
					var nx = k + 1;
					if (nx < insns.length && !blockStart[nx] && states[nx] != null
						&& (insns[nx].op == 0x57 && !Jvm.wide(ret) || insns[nx].op == 0x58 && Jvm.wide(ret))) {
						skip[nx] = true;
						popped = true;
					} else
						dst = dest(d, ret, 8, k + 1);
				}
				call(dop, regs, RMethod(Jvm.desc(r.owner), r.name, sig.ret, params));
				if (ret != "V" && !popped) {
					asm.raw([resultOp(ret) | dst << 8]);
					result(d, dst, ret);
				}
			case 0xba:
				invokeDynamic(i, k, depth);
			case 0xbb:
				// (new, dup, the arguments, <init>, then a store: the object made in the local)
				var into = newInto(k, depth);
				if (into >= 0) {
					var r = lreg(into);
					clobber([r]);
					asm.ref(0x22, r, RType(Jvm.desc(c.pool.cls(i.a))));
					push(r, "U" + i.pc);
				} else {
					var r = dest(depth, "U" + i.pc, 8, -1);
					asm.ref(0x22, r, RType(Jvm.desc(c.pool.cls(i.a))));
					result(depth, r, "U" + i.pc);
				}
			case 0xbc | 0xbd:
				var t = op == 0xbc ? "[" + PRIMS.get(i.a) : "[" + Jvm.desc(c.pool.cls(i.a));
				var size = use(depth - 1, 4, 0);
				drop(1);
				var r = dest(depth - 1, t, 4, k + 1);
				asm.ref(0x23, r | size << 4, RType(t));
				result(depth - 1, r, t);
			case 0xbe:
				var a = use(depth - 1, 4, 0);
				drop(1);
				var r = dest(depth - 1, "I", 4, k + 1);
				asm.raw([0x21 | r << 8 | a << 12]);
				result(depth - 1, r, "I");
			case 0xbf:
				var r = use(depth - 1, 8, 0);
				asm.raw([0x27 | r << 8]);
			case 0xc0:
				// (on the word's own register: check-cast retypes it, and a local
				// or another word read through an alias keeps its type; or in the
				// local the next instruction stores it to)
				var t = Jvm.desc(c.pool.cls(i.a));
				var r = stk[depth - 1], cw = canon(depth - 1);
				// (an upcast, by the libraries' own hierarchy: nothing to check)
				if (host.jvm.assignable(typ[depth - 1], t)) return;
				var nx = k + 1, covered = false;
				for (h in jcode.handlers)
					if (h.start <= i.pc && h.end > i.pc) covered = true;
				// (not when a handler would see the local overwritten before the cast throws)
				if (!covered && nx < insns.length && insns[nx].op == 0x3a && !blockStart[nx] && states[nx] != null && lreg(insns[nx].a) < 256) {
					var l = lreg(insns[nx].a);
					drop(1);
					clobber([l]);
					move(l, r, "L");
					asm.ref(0x1f, l, RType(t));
					skip[nx] = true;
					return;
				}
				// (in place: an Object narrowed, every later use of it takes the
				// subtype too; or a local no instruction reads again, aliased by nothing else)
				if (r != cw && r < 256 && (typ[depth - 1] == "Ljava/lang/Object;" || deadLocal(k, r, depth - 1))) {
					asm.ref(0x1f, r, RType(t));
					typ[depth - 1] = t;
					return;
				}
				if (r != cw) {
					if (cw >= 256) throw "check-cast past v255";
					move(cw, r, "L");
					r = cw;
				}
				asm.ref(0x1f, r, RType(t));
				stk[depth - 1] = r;
				typ[depth - 1] = t;
			case 0xc1:
				var obj = use(depth - 1, 4, 0);
				drop(1);
				var r = dest(depth - 1, "I", 4, k + 1);
				asm.ref(0x20, r | obj << 4, RType(Jvm.desc(c.pool.cls(i.a))));
				result(depth - 1, r, "I");
			case 0xc2 | 0xc3:
				var r = use(depth - 1, 8, 0);
				drop(1);
				asm.raw([(op == 0xc2 ? 0x1d : 0x1e) | r << 8]);
			case 0xc5:
				var t = Jvm.desc(c.pool.cls(i.a)), d = depth - i.b;
				materialize(d);
				var dims = [for (w in d...depth) stk[w]];
				drop(i.b);
				call(Dalvik.FILLED_NEW_ARRAY, dims, RType("[I"));
				asm.raw([0x0c | tmp(1) << 8]);
				var comp = t.substr(i.b);
				if (comp.length == 1) asm.ref(0x62, tmp(0), RField("Ljava/lang/" + WRAPPERS.get(comp) + ";", "TYPE", "Ljava/lang/Class;")) else
					asm.ref(0x1c, tmp(0), RType(comp));
				call(Dalvik.INVOKE_STATIC, [tmp(0), tmp(1)], RMethod("Ljava/lang/reflect/Array;", "newInstance", "Ljava/lang/Object;", ["Ljava/lang/Class;", "[I"]));
				var r = dest(d, t, 8, k + 1);
				asm.raw([0x0c | r << 8]);
				asm.ref(0x1f, r, RType(t));
				result(d, r, t);
			case o: throw 'opcode 0x${StringTools.hex(o, 2)}';
		}
	}

	// the local a new object is stored to right after its constructor, when
	// nothing between reads or writes it, jumps in or can throw to a handler
	function newInto(k:Int, depth:Int):Int {
		var n = insns.length, pc = insns[k].pc, u = "U" + pc;
		if (k + 1 >= n || insns[k + 1].op != 0x59 || blockStart[k + 1]) return -1;
		var j = k + 2;
		while (j < n) {
			var s = states[j];
			if (s == null || blockStart[j]) return -1;
			var i = insns[j];
			if (i.op == 0xb7 && s.stack.length > depth + 1 && s.stack[depth + 1] == u) {
				var r = c.pool.ref(i.a);
				if (r.name != "<init>" || s.stack.length - wordsOf(Jvm.signature(r.desc).params) - 1 != depth + 1) return -1;
				break;
			}
			if (targets(i).length > 0 || !falls(i)) return -1;
			j++;
		}
		if (j + 1 >= n || insns[j + 1].op != 0x3a || blockStart[j + 1] || states[j + 1] == null) return -1;
		var l = insns[j + 1].a;
		if (lreg(l) >= 256) return -1;
		for (x in k...j + 1) {
			var i = insns[x];
			if ((i.op >= 0x15 && i.op <= 0x19 || i.op >= 0x36 && i.op <= 0x3a || i.op == 0x84) && (i.a == l || i.a + 1 == l)) return -1;
		}
		for (h in jcode.handlers)
			if (h.start <= insns[j].pc && h.end > pc) return -1;
		return l;
	}

	var liveOut:Null<Array<Array<Int>>> = null;

	// whether register r is a local's that no path reads after instruction k (stk's other words not on it)
	function deadLocal(k:Int, r:Int, w:Int):Bool {
		for (x in 0...stk.length)
			if (x != w && stk[x] == r) return false;
		var l = -1;
		for (i in 0...jcode.maxLocals)
			if (lreg(i) == r) l = i;
		if (l < 0 || jcode.maxLocals > 256) return false;
		if (liveOut == null) liveness();
		return liveOut[k][l >> 5] & (1 << (l & 31)) == 0;
	}

	// the locals live after each instruction (read on some path before a write),
	// a handler's reads live through its range
	function liveness() {
		var n = insns.length, words = (jcode.maxLocals >> 5) + 1;
		var liveIn = [for (_ in 0...n) [for (_ in 0...words) 0]];
		liveOut = [for (_ in 0...n) [for (_ in 0...words) 0]];
		var changed = true;
		while (changed) {
			changed = false;
			var k = n - 1;
			while (k >= 0) {
				var i = insns[k], out = liveOut[k];
				var succ = targets(i);
				if (falls(i) && k + 1 < n) succ.push(insns[k + 1].pc);
				for (h in jcode.handlers)
					if (i.pc >= h.start && i.pc < h.end) succ.push(h.handler);
				for (pc in succ) {
					var x = liveIn[index.get(pc)];
					for (j in 0...words)
						if (out[j] | x[j] != out[j]) {
							out[j] |= x[j];
							changed = true;
						}
				}
				var inn = out.copy();
				if (i.op >= 0x36 && i.op <= 0x3a) {
					inn[i.a >> 5] &= ~(1 << (i.a & 31));
					if (i.op == 0x37 || i.op == 0x39) inn[(i.a + 1) >> 5] &= ~(1 << ((i.a + 1) & 31));
				}
				if (i.op >= 0x15 && i.op <= 0x19 || i.op == 0x84 || i.op == 0xa9) {
					inn[i.a >> 5] |= 1 << (i.a & 31);
					if (i.op == 0x16 || i.op == 0x18) inn[(i.a + 1) >> 5] |= 1 << ((i.a + 1) & 31);
				}
				var cur = liveIn[k];
				for (j in 0...words)
					if (cur[j] != inn[j]) {
						cur[j] = inn[j];
						changed = true;
					}
				k--;
			}
		}
	}

	// the locals' registers: the most used lowest (4-bit instructions reach
	// v0-v15), a wide one's two words together; the arguments in place at the
	// end, or copied in by the prologue (straddle) when that costs fewer moves
	function number(at:Int) {
		var n = jcode.maxLocals, uses = [for (_ in 0...n) 0], wideAt = [for (_ in 0...n + 1) false];
		for (k in 0...insns.length) {
			var i = insns[k];
			if (states[k] == null) continue;
			if (i.op >= 0x15 && i.op <= 0x19 || i.op >= 0x36 && i.op <= 0x3a || i.op == 0x84) {
				uses[i.a]++;
				if (i.op == 0x16 || i.op == 0x18 || i.op == 0x37 || i.op == 0x39) wideAt[i.a] = true;
			}
		}
		// (units: a local, or a wide one's pair; overlapping pairs keep the identity)
		var units = [], k = 0, plain = false;
		while (k < n) {
			if (wideAt[k]) {
				if (k + 1 < n && wideAt[k + 1]) plain = true;
				units.push({at: k, size: 2, uses: uses[k] + (k + 1 < n ? uses[k + 1] : 0)});
				k += 2;
			} else {
				units.push({at: k, size: 1, uses: uses[k]});
				k++;
			}
		}
		function layout(copied:Bool):Array<Int> {
			var regs = [for (_ in 0...n) 0], next = 0;
			var order = [for (u in units) if (copied || u.at >= argWords) u];
			if (!plain) order.sort((a, b) -> b.uses - a.uses);
			for (u in order) {
				for (j in 0...u.size)
					if (u.at + j < n) regs[u.at + j] = next + j;
				next += u.size;
			}
			if (!copied) for (j in 0...argWords)
				regs[j] = next + j;
			return regs;
		}
		function cost(regs:Array<Int>):Int {
			var c = 0;
			for (j in 0...n)
				if (at + regs[j] >= 16) c += uses[j];
			return c;
		}
		var inPlace = straddle ? null : layout(false), copied = layout(true);
		if (inPlace != null && (at + n <= 16 || cost(inPlace) <= cost(copied) + argWords)) regOf = inPlace else {
			straddle = true;
			regOf = copied;
		}
	}

	function isPrivate(r:JRef):Bool
		return host.jvm.isPrivate(r.owner, r.name, r.desc);

	// an int operation with a constant operand as its literal (lit8, lit16): done
	function literal(o:Int, d:Int, k:Int):Bool {
		var second = kon[d + 1], first = kon[d];
		var commutes = o == 0x60 || o == 0x68 || o == 0x7e || o == 0x80 || o == 0x82;
		var x = -1, v:Null<Int> = null, lit8 = -1, lit16 = -1;
		if (second != null) {
			x = d;
			v = second;
		} else if (first != null && (commutes || o == 0x64)) {
			x = d + 1;
			v = first;
		} else return false;
		switch o {
			case 0x60: lit8 = 0xd8; lit16 = 0xd0;
			case 0x64:
				if (x == d) {
					v = -v;
					lit8 = 0xd8;
					lit16 = 0xd0;
				} else {
					lit8 = 0xd9;
					lit16 = 0xd1;
				}
			case 0x68: lit8 = 0xda; lit16 = 0xd2;
			case 0x6c if (x == d): lit8 = 0xdb; lit16 = 0xd3;
			case 0x70 if (x == d): lit8 = 0xdc; lit16 = 0xd4;
			case 0x7e: lit8 = 0xdd; lit16 = 0xd5;
			case 0x80: lit8 = 0xde; lit16 = 0xd6;
			case 0x82: lit8 = 0xdf; lit16 = 0xd7;
			case 0x78 if (x == d): lit8 = 0xe0;
			case 0x7a if (x == d): lit8 = 0xe1;
			case 0x7c if (x == d): lit8 = 0xe2;
			case _: return false;
		}
		if (v >= -128 && v < 128 && lit8 >= 0) {
			var b = use(x, 8, 0);
			drop(2);
			var r = dest(d, "I", 8, k + 1);
			asm.raw([lit8 | r << 8, b | (v & 0xff) << 8]);
			result(d, r, "I");
			return true;
		}
		if (v >= -32768 && v < 32768 && lit16 >= 0) {
			var b = use(x, 4, 0);
			drop(2);
			var r = dest(d, "I", 4, k + 1);
			asm.raw([lit16 | r << 8 | b << 12, v & 0xffff]);
			result(d, r, "I");
			return true;
		}
		return false;
	}

	// dup_x1, dup_x2, dup2_x1, dup2_x2, swap: the words moved through the temporaries
	function permute(o:Int, depth:Int) {
		var n = switch o {
			case 0x5a | 0x5f: 2;
			case 0x5b | 0x5d: 3;
			case _: 4;
		};
		var from = depth - n;
		for (w in from...depth)
			realize(w);
		var w = from;
		while (w < depth) {
			var t = typ[w];
			if (t == "-") {
				w++;
				continue;
			}
			var r = stk[w];
			if (r >= canon(from) && r < canon(depth)) {
				var at = tmp(w - from);
				move(at, r, t);
				stk[w] = at;
				if (kind(t) == 2) stk[w + 1] = at + 1;
			}
			w += kind(t) == 2 ? 2 : 1;
		}
		var words = [for (k in from...depth) {r: stk[k], t: typ[k]}];
		var x = [for (k in 0...n) words[n - 1 - k]];
		// (x[0] the top word)
		var order = switch o {
			case 0x5a: [x[0], x[1], x[0]];
			case 0x5b: [x[0], x[2], x[1], x[0]];
			case 0x5d: [x[1], x[0], x[2], x[1], x[0]];
			case 0x5e: [x[1], x[0], x[3], x[2], x[1], x[0]];
			case _: [x[0], x[1]];
		};
		drop(n);
		for (e in order)
			word(e.r, e.t, null);
		materialize(from);
	}

	function invokeDynamic(i:Insn, k:Int, depth:Int) {
		var b = indy(i), nt = indyNameType(i), sig = Jvm.signature(nt.desc);
		var nw = wordsOf(sig.params), d = depth - nw;
		for (x in d...depth)
			realize(x);
		var values = [], w = d;
		for (p in sig.params) {
			values.push({r: stk[w], t: p});
			w += Jvm.wide(p) ? 2 : 1;
		}
		var owner = b.method.owner + "." + b.method.name;
		switch owner {
			case "java/lang/invoke/LambdaMetafactory.metafactory" | "java/lang/invoke/LambdaMetafactory.altMetafactory":
				var sam = switch b.args[0] {
					case CMethodType(x): x;
					case _: throw "a lambda without its method type";
				};
				var impl = switch b.args[1] {
					case CHandle(h): h;
					case _: throw "a lambda without its implementation";
				};
				var descs = [sam], markers = [];
				if (b.method.name == "altMetafactory") {
					var flags = switch b.args[3] {
						case CInt(f): f;
						case _: 0;
					}, at = 4;
					if (flags & 1 != 0) markers.push("java/io/Serializable");
					if (flags & 2 != 0) {
						var nm = switch b.args[at++] {
							case CInt(v): v;
							case _: 0;
						};
						for (_ in 0...nm)
							switch b.args[at++] {
								case CClass(cl): markers.push(cl);
								case _:
							}
					}
					if (flags & 4 != 0) {
						var nb = switch b.args[at++] {
							case CInt(v): v;
							case _: 0;
						};
						for (_ in 0...nb)
							switch b.args[at++] {
								case CMethodType(x): if (descs.indexOf(x) < 0) descs.push(x);
								case _:
							}
					}
				}
				if (impl.kind == 7 && impl.owner != c.name) throw "a lambda calling a superclass's method (invokespecial)";
				var name = c.name + "$$ExternalSyntheticLambda" + host.lambdas.length;
				var iface = Jvm.internal(sig.ret);
				host.lambda(name, sig.params, iface, nt.name, descs, markers, impl);
				var self = "L" + name + ";";
				drop(nw);
				asm.ref(0x22, tmp(0), RType(self));
				var regs = block([{r: tmp(0), t: self}].concat(values), 0);
				if (regs[0] != tmp(0)) throw "a lambda's block";
				call(Dalvik.INVOKE_DIRECT, regs, RMethod(self, "<init>", "V", sig.params));
				var r = dest(d, sig.ret, 8, k + 1);
				move(r, tmp(0), "L");
				result(d, r, sig.ret);
			case "java/lang/invoke/StringConcatFactory.makeConcatWithConstants" | "java/lang/invoke/StringConcatFactory.makeConcat":
				var pieces:Array<{arg:Int, text:String}> = [];
				if (b.method.name == "makeConcat") pieces = [for (j in 0...values.length) {arg: j, text: null}] else {
					var recipe = switch b.args[0] {
						case CString(x): Dex.units(x);
						case _: throw "a concatenation without its recipe";
					};
					var lit = [], arg = 0, cst = 1;
					function flush() {
						if (lit.length > 0) pieces.push({arg: -1, text: Jvm.escape(lit)});
						lit = [];
					}
					for (u in recipe)
						if (u == 1) {
							flush();
							pieces.push({arg: arg++, text: null});
						} else if (u == 2) {
							flush();
							switch b.args[cst++] {
								case CString(x): pieces.push({arg: -1, text: x});
								case CInt(v): pieces.push({arg: -1, text: Std.string(v)});
								case _: throw "a concatenation's constant";
							}
						} else lit.push(u);
					flush();
				}
				drop(nw);
				var sb = "Ljava/lang/StringBuilder;";
				asm.ref(0x22, tmp(0), RType(sb));
				call(Dalvik.INVOKE_DIRECT, [tmp(0)], RMethod(sb, "<init>", "V", []));
				for (p in pieces) {
					if (p.arg < 0) {
						if (p.text == "") continue;
						asm.string(tmp(1), p.text);
						call(Dalvik.INVOKE_VIRTUAL, [tmp(0), tmp(1)], RMethod(sb, "append", sb, ["Ljava/lang/String;"]));
						continue;
					}
					var v = values[p.arg];
					var at = switch v.t {
						case "Ljava/lang/String;": v.t;
						case "Z" | "C" | "J" | "F" | "D" | "I": v.t;
						case "B" | "S": "I";
						case "Ljava/lang/CharSequence;": v.t;
						case _: "Ljava/lang/Object;";
					};
					call(Dalvik.INVOKE_VIRTUAL, block([{r: tmp(0), t: sb}, v], 0), RMethod(sb, "append", sb, [at]));
				}
				call(Dalvik.INVOKE_VIRTUAL, [tmp(0)], RMethod(sb, "toString", "Ljava/lang/String;", []));
				var r = dest(d, "Ljava/lang/String;", 8, k + 1);
				asm.raw([0x0c | r << 8]);
				result(d, r, "Ljava/lang/String;");
			case _:
				throw 'invokedynamic of $owner';
		}
	}
}

private typedef State = {locals:Array<String>, stack:Array<String>};

private typedef Insn = {
	pc:Int,
	op:Int,
	len:Int,
	a:Int,
	b:Int,
	?keys:Array<Int>,
	?targets:Array<Int>,
	?dflt:Int
};
