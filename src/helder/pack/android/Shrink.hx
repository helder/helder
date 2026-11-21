package helder.pack.android;

import haxe.io.Bytes;
import helder.pack.android.ClassFile;

// What of the libraries' classes an app can reach, from its roots (keep
// rules: the API the app calls, the libraries' own proguard.txt, Keep's
// defaults; the manifest's components), as R8's shrinking without its
// optimisations or renaming:
// - a class is kept when code names it (its supertypes, static
//   initializer, the types of its kept members' signatures with it), a
//   method when called, a field when read or written (each resolved up to
//   its declaring class), keep rules' members when they match (a kept
//   virtual method as if called: the app's code calls it);
// - a virtual call keeps the implementations of the classes instantiated
//   (`new`, a constructor kept by a rule or reflection) below the type
//   called on, defaults included;
// - an instantiated class whose supertypes leave the libraries (the
//   framework's: Binder, Activity, Runnable; Object's equals, hashCode,
//   toString, finalize and clone always) keeps every method that could
//   override theirs: their methods are unknown here (no android.jar);
// - reflection seeds: Class.forName of a constant, and a constant name
//   with a constant class where a method reads fields or methods by name
//   (getDeclaredField, getMethod, the atomic field updaters' newUpdater);
//   a class constant of a framework subclass (an Intent's component) is
//   instantiated with its no-argument constructor.
class Shrink {
	final world:Map<String, ClassFile>;
	final rules:Array<Keep>;
	final live = new Map<String, Bool>();
	final made = new Map<String, Bool>();
	final methods = new Map<String, Bool>();
	final fields = new Map<String, Bool>();
	// the signatures called virtually on each type, the instantiated classes below each type
	final invoked = new Map<String, Array<String>>();
	final invokedSet = new Map<String, Bool>();
	final below = new Map<String, Array<String>>();
	final closures = new Map<String, Array<String>>();
	final work:Array<{c:ClassFile, m:JMethod}> = [];

	public function new(world:Map<String, ClassFile>, rules:Array<Keep>) {
		this.world = world;
		this.rules = rules;
	}

	// ---- the results

	public function classes():Array<ClassFile>
		return [for (n => c in world) if (live.exists(n)) c];

	public function keepsClass(name:String):Bool
		return live.exists(name);

	public function keepsMethod(c:ClassFile, m:JMethod):Bool
		return methods.exists(c.name + "." + m.name + m.desc);

	public function keepsField(c:ClassFile, f:JField):Bool
		return fields.exists(c.name + "." + f.name + ":" + f.desc);

	public function count():{classes:Int, methods:Int, fields:Int} {
		var n = 0, m = 0, f = 0;
		for (_ in live) n++;
		for (_ in methods) m++;
		for (_ in fields) f++;
		return {classes: n, methods: m, fields: f};
	}

	// ---- roots

	// the rules applied (keep and with ones to every class; members ones
	// as classes become kept), then everything reachable
	public function run() {
		for (c in world)
			for (r in rules)
				if (r.kind != "members") rule(r, c);
		drain();
	}

	// a class the framework makes (a manifest's component): its no-argument constructor
	public function component(name:String) {
		var c = world.get(name);
		if (c == null) return;
		instantiate(name);
		var m = c.method("<init>", "()V");
		if (m != null) method(c, m);
		drain();
	}

	function rule(r:Keep, c:ClassFile) {
		if (!r.classMatches(c, closure(c.name), n -> world.get(n))) return;
		var fs = [], ms = [];
		for (spec in r.members) {
			var any = false;
			for (f in c.fields)
				if (r.fieldMatches(spec, f)) {
					fs.push(f);
					any = true;
				}
			for (m in c.methods)
				if (r.methodMatches(spec, m)) {
					ms.push(m);
					any = true;
				}
			if (!any && r.kind == "with") return;
		}
		if (r.kind != "members") liveClass(c.name);
		for (f in fs)
			field(c, f);
		// (a kept method may be called from outside: its overrides with it)
		for (m in ms) {
			if (m.name == "<init>") instantiate(c.name);
			method(c, m);
			if (m.access & (ClassFile.STATIC | ClassFile.PRIVATE) == 0 && m.name != "<init>") invoke(c.name, m.name, m.desc, true);
		}
	}

	// ---- reachability

	function drain() {
		while (work.length > 0) {
			var w = work.pop();
			scan(w.c, w.m);
		}
	}

	// the class and its supertypes, the library's and the framework's names alike
	function closure(name:String):Array<String> {
		var cached = closures.get(name);
		if (cached != null) return cached;
		var out = [name], c = world.get(name);
		closures.set(name, out);
		if (c != null) for (s in (c.superName == null ? [] : [c.superName]).concat(c.interfaces))
			for (x in closure(s))
				if (out.indexOf(x) < 0) out.push(x);
		return out;
	}

	function liveType(desc:String) {
		var k = 0;
		while (desc.charAt(k) == "[")
			k++;
		if (desc.charAt(k) == "L") liveClass(desc.substring(k + 1, desc.length - 1));
	}

	function liveClass(name:String) {
		if (live.exists(name)) return;
		var c = world.get(name);
		if (c == null) return;
		live.set(name, true);
		if (c.superName != null) liveClass(c.superName);
		for (i in c.interfaces)
			liveClass(i);
		var init = c.method("<clinit>", "()V");
		if (init != null) method(c, init);
		for (r in rules)
			if (r.kind == "members") rule(r, c);
	}

	static final OBJECT = ["equals(Ljava/lang/Object;)Z", "hashCode()I", "toString()Ljava/lang/String;", "finalize()V", "clone()Ljava/lang/Object;"];

	function instantiate(name:String) {
		if (made.exists(name) || !world.exists(name)) return;
		made.set(name, true);
		liveClass(name);
		var cl = closure(name);
		for (s in cl) {
			var b = below.get(s);
			if (b == null) below.set(s, b = []);
			b.push(name);
			var sigs = invoked.get(s);
			if (sigs != null) for (sig in sigs.copy())
				implementation(name, sig);
		}
		for (sig in OBJECT)
			implementation(name, sig);
		// (a framework supertype: every method that could override one of its;
		// an interface of FRAMEWORK, its methods; a marker's, none)
		var superclass = false, iface = false, names = new Map<String, Bool>();
		for (s in cl)
			if (s != "java/lang/Object" && !world.exists(s)) {
				if (!isInterfaceName(name, s)) superclass = true else {
					var known = FRAMEWORK.get(s);
					if (known == null) iface = true else for (n in known) names.set(n, true);
				}
			}
		var any = names.keys().hasNext();
		if (superclass || iface || any) for (s in cl) {
			var k = world.get(s);
			if (k == null) continue;
			for (m in k.methods)
				if (m.access & (ClassFile.STATIC | ClassFile.PRIVATE) == 0 && m.name != "<init>"
					&& (superclass || (iface && m.access & ClassFile.PUBLIC != 0) || names.exists(m.name))) method(k, m);
		}
	}

	// the methods of the framework's interfaces most classes implement (the
	// others: every public method kept)
	static final FRAMEWORK = [
		"java/io/Serializable" => [], "java/lang/Cloneable" => [], "java/util/RandomAccess" => [], "java/util/EventListener" => [],
		"java/lang/Runnable" => ["run"], "java/util/concurrent/Callable" => ["call"], "java/util/Comparator" => ["compare", "equals"],
		"java/lang/Comparable" => ["compareTo"], "java/lang/AutoCloseable" => ["close"], "java/io/Closeable" => ["close"],
		"java/util/concurrent/Executor" => ["execute"], "java/util/concurrent/ThreadFactory" => ["newThread"],
		"java/lang/Thread$UncaughtExceptionHandler" => ["uncaughtException"], "java/lang/reflect/InvocationHandler" => ["invoke"],
		"java/util/Iterator" => ["hasNext", "next", "remove", "forEachRemaining"], "java/lang/Iterable" => ["iterator", "forEach", "spliterator"],
		"java/util/Map$Entry" => ["getKey", "getValue", "setValue"], "android/os/Handler$Callback" => ["handleMessage"],
		"android/content/ServiceConnection" => ["onServiceConnected", "onServiceDisconnected", "onBindingDied", "onNullBinding"],
		"android/os/IBinder$DeathRecipient" => ["binderDied"], "android/os/IInterface" => ["asBinder"],
		"android/os/Parcelable" => ["describeContents", "writeToParcel"], "android/os/Parcelable$Creator" => ["createFromParcel", "newArray"],
		"android/os/Parcelable$ClassLoaderCreator" => ["createFromParcel", "newArray"], "java/util/function/Supplier" => ["get"],
		"java/util/function/Consumer" => ["accept", "andThen"], "java/util/function/Function" => ["apply", "andThen", "compose"],
		"java/util/function/Predicate" => ["test", "and", "or", "negate"], "java/util/function/BiFunction" => ["apply", "andThen"],
		"java/util/concurrent/Future" => ["cancel", "isCancelled", "isDone", "get"], "android/content/ComponentCallbacks" => ["onConfigurationChanged", "onLowMemory"],
		"android/content/ComponentCallbacks2" => ["onConfigurationChanged", "onLowMemory", "onTrimMemory"]
	];

	// whether an outside name is one of the interfaces the library's classes of name's closure implement
	function isInterfaceName(name:String, outside:String):Bool {
		for (s in closure(name)) {
			var c = world.get(s);
			if (c != null && c.interfaces.indexOf(outside) >= 0) return true;
		}
		return false;
	}

	// the method a class's instance runs for sig: its own or inherited, else a default
	function implementation(name:String, sig:String) {
		var at = name;
		while (at != null) {
			var c = world.get(at);
			if (c == null) return;
			for (m in c.methods)
				if (m.name + m.desc == sig && m.access & ClassFile.STATIC == 0) {
					if (m.access & ClassFile.ABSTRACT == 0) {
						method(c, m);
						return;
					}
				}
			at = c.superName;
		}
		for (s in closure(name)) {
			var c = world.get(s);
			if (c == null || c.access & ClassFile.INTERFACE == 0) continue;
			for (m in c.methods)
				if (m.name + m.desc == sig && m.access & (ClassFile.ABSTRACT | ClassFile.STATIC) == 0) method(c, m);
		}
	}

	// a reference's declaration: the class's, a superclass's, else an interface's
	function declaration(owner:String, name:String, desc:String):Null<{c:ClassFile, m:JMethod}> {
		var at = owner;
		while (at != null) {
			var c = world.get(at);
			if (c == null) break;
			var m = c.method(name, desc);
			if (m != null) return {c: c, m: m};
			at = c.superName;
		}
		for (s in closure(owner)) {
			var c = world.get(s);
			if (c == null) continue;
			var m = c.method(name, desc);
			if (m != null) return {c: c, m: m};
		}
		return null;
	}

	function invoke(owner:String, name:String, desc:String, virtual:Bool) {
		liveClass(owner);
		var d = declaration(owner, name, desc);
		if (d != null) method(d.c, d.m);
		if (!virtual || name == "<init>") return;
		var sig = name + desc, key = owner + "." + sig;
		if (invokedSet.exists(key)) return;
		invokedSet.set(key, true);
		var sigs = invoked.get(owner);
		if (sigs == null) invoked.set(owner, sigs = []);
		sigs.push(sig);
		var b = below.get(owner);
		if (b != null) for (n in b.copy())
			implementation(n, sig);
	}

	function method(c:ClassFile, m:JMethod) {
		var key = c.name + "." + m.name + m.desc;
		if (methods.exists(key)) return;
		methods.set(key, true);
		liveClass(c.name);
		var s = Jvm.signature(m.desc);
		for (p in s.params)
			liveType(p);
		liveType(s.ret);
		if (m.code != null) work.push({c: c, m: m});
	}

	function field(c:ClassFile, f:JField) {
		var key = c.name + "." + f.name + ":" + f.desc;
		if (fields.exists(key)) return;
		fields.set(key, true);
		liveClass(c.name);
		liveType(f.desc);
	}

	function fieldRef(owner:String, name:String, desc:String) {
		liveClass(owner);
		for (s in closure(owner)) {
			var c = world.get(s);
			if (c == null) continue;
			var f = c.field(name, desc);
			if (f != null) {
				field(c, f);
				return;
			}
		}
	}

	// a class the framework or reflection may make
	function seed(name:String) {
		var c = world.get(name);
		if (c == null) return;
		instantiate(name);
		for (m in c.methods)
			if (m.name == "<init>") method(c, m);
	}

	static final BY_NAME = [
		"getDeclaredField", "getField", "getDeclaredMethod", "getMethod", "newUpdater", "getDeclaredFields", "getDeclaredMethods"
	];

	function scan(c:ClassFile, m:JMethod) {
		var code = m.code.code, p = c.pool;
		for (h in m.code.handlers)
			if (h.type != null) liveClass(h.type);
		var strings = [], classes = [], reflects = false, lastString:Null<String> = null;
		walk(code, (op, pc) -> {
			inline function u2()
				return code.get(pc + 1) << 8 | code.get(pc + 2);
			switch op {
				case 0x12 | 0x13:
					var i = op == 0x12 ? code.get(pc + 1) : u2();
					switch p.value(i) {
						case CString(s):
							strings.push(s);
							lastString = s;
							return;
						case CClass(n):
							liveType(Jvm.desc(n));
							classes.push(n);
							// (a framework class's subclass named by a constant: an Intent's component)
							var cl = closure(n);
							for (s in cl)
								if (s != "java/lang/Object" && !world.exists(s) && world.exists(n)) {
									var k = world.get(n);
									if (k.access & (ClassFile.INTERFACE | ClassFile.ABSTRACT) == 0) {
										instantiate(n);
										var ctor = k.method("<init>", "()V");
										if (ctor != null) method(k, ctor);
									}
									break;
								}
						case _:
					}
				case 0xb2 | 0xb3 | 0xb4 | 0xb5:
					var r = p.ref(u2());
					fieldRef(r.owner, r.name, r.desc);
				case 0xb6 | 0xb9:
					var r = p.ref(u2());
					invoke(r.owner, r.name, r.desc, true);
					if (BY_NAME.indexOf(r.name) >= 0) reflects = true;
				case 0xb7:
					var r = p.ref(u2());
					invoke(r.owner, r.name, r.desc, false);
				case 0xb8:
					var r = p.ref(u2());
					invoke(r.owner, r.name, r.desc, false);
					if (r.owner == "java/lang/Class" && r.name == "forName" && lastString != null) seed(lastString.split(".").join("/"));
					if (BY_NAME.indexOf(r.name) >= 0) reflects = true;
				case 0xba:
					var o = p.at[u2()];
					var b = c.bootstraps[p.u2(o)];
					var nt = p.at[p.u2(o + 2)];
					liveType(Jvm.signature(p.utf8(p.u2(nt + 2))).ret);
					if (b.method.owner == "java/lang/invoke/LambdaMetafactory") {
						for (a in b.args)
							switch a {
								case CHandle(h):
									switch h.kind {
										case 5 | 9: invoke(h.owner, h.name, h.desc, true);
										case 8:
											seed(h.owner);
											invoke(h.owner, h.name, h.desc, false);
										case _: invoke(h.owner, h.name, h.desc, false);
									}
								case CClass(n): liveClass(n);
								case _:
							}
					}
				case 0xbb:
					var n = p.cls(u2());
					instantiate(n);
				case 0xbd | 0xc0 | 0xc1 | 0xc5:
					liveType(Jvm.desc(p.cls(u2())));
				case _:
			}
			lastString = null;
		});
		if (reflects) for (n in classes) {
			var k = world.get(n);
			if (k == null) continue;
			for (s in strings) {
				for (f in k.fields)
					if (f.name == s) field(k, f);
				for (x in k.methods)
					if (x.name == s) method(k, x);
			}
		}
	}

	// each instruction's opcode and offset
	public static function walk(code:Bytes, f:(Int, Int) -> Void) {
		var pc = 0, n = code.length;
		inline function s4(o:Int)
			return code.get(o) << 24 | code.get(o + 1) << 16 | code.get(o + 2) << 8 | code.get(o + 3);
		while (pc < n) {
			var op = code.get(pc);
			f(op, pc);
			pc += switch op {
				case 0x10 | 0x12 | 0xbc | 0xa9: 2;
				case o if (o >= 0x15 && o <= 0x19 || o >= 0x36 && o <= 0x3a): 2;
				case 0x11 | 0x13 | 0x14 | 0x84 | 0xbb | 0xbd | 0xc0 | 0xc1 | 0xc6 | 0xc7: 3;
				case o if (o >= 0x99 && o <= 0xa8 || o >= 0xb2 && o <= 0xb8): 3;
				case 0xc8 | 0xc9 | 0xb9 | 0xba: 5;
				case 0xc5: 4;
				case 0xc4: code.get(pc + 1) == 0x84 ? 6 : 4;
				case 0xaa:
					var at = (pc + 4) & ~3;
					at + 12 + 4 * (s4(at + 8) - s4(at + 4) + 1) - pc;
				case 0xab:
					var at = (pc + 4) & ~3;
					at + 8 + 8 * s4(at + 4) - pc;
				case _: 1;
			}
		}
	}
}
