package helder.pack.android;

import haxe.io.Bytes;

// A JVM class file read (the JVM specification's chapter 4): the constant
// pool, fields (ConstantValue), methods (Code: its bytecode, exception
// table and StackMapTable's frames), BootstrapMethods, the annotations'
// types (for keep rules), InnerClasses, NestHost and NestMembers. Written
// from the specification for Jvm's translation to Dalvik.
//
// Strings are kept as Dex's pools keep them: ASCII as it is, any other
// UTF-16 unit (and NUL, \x01) as \x01 and four hex digits, so that a
// string's text is the same on every Haxe target, lone surrogates too
// (Dex.units reads them back).
class ClassFile {
	public static inline var PUBLIC = 0x1;
	public static inline var PRIVATE = 0x2;
	public static inline var PROTECTED = 0x4;
	public static inline var STATIC = 0x8;
	public static inline var FINAL = 0x10;
	public static inline var SYNCHRONIZED = 0x20;
	public static inline var BRIDGE = 0x40;
	public static inline var VARARGS = 0x80;
	public static inline var NATIVE = 0x100;
	public static inline var INTERFACE = 0x200;
	public static inline var ABSTRACT = 0x400;
	public static inline var SYNTHETIC = 0x1000;
	public static inline var ANNOTATION = 0x2000;
	public static inline var ENUM = 0x4000;

	public var version:Int;
	public var access:Int;
	// internal names (java/lang/Object); superName null for Object itself
	public var name:String;
	public var superName:Null<String>;
	public var interfaces:Array<String>;
	public var fields:Array<JField> = [];
	public var methods:Array<JMethod> = [];
	// the annotations' descriptors, visible and invisible (keep rules match them)
	public var annotations:Array<String> = [];
	public var bootstraps:Array<{method:JHandle, args:Array<JConst>}> = [];
	public var inner:Array<{name:String, outer:Null<String>, simple:Null<String>, access:Int}> = [];
	public var nestHost:Null<String>;
	// EnclosingMethod's class (a local or anonymous class's)
	public var enclosing:Null<String>;
	public var nestMembers:Array<String> = [];
	public var pool:JPool;

	function new() {}

	public function method(name:String, desc:String):Null<JMethod> {
		for (m in methods)
			if (m.name == name && m.desc == desc) return m;
		return null;
	}

	public function field(name:String, desc:String):Null<JField> {
		for (f in fields)
			if (f.name == name && f.desc == desc) return f;
		return null;
	}

	public static function read(b:Bytes):ClassFile {
		if (b.length < 10 || b.get(0) != 0xca || b.get(1) != 0xfe || b.get(2) != 0xba || b.get(3) != 0xbe) throw "not a class file";
		var c = new ClassFile(), at = 8;
		inline function u1()
			return b.get(at++);
		function u2() {
			var v = b.get(at) << 8 | b.get(at + 1);
			at += 2;
			return v;
		}
		function u4() {
			var v = b.get(at) << 24 | b.get(at + 1) << 16 | b.get(at + 2) << 8 | b.get(at + 3);
			at += 4;
			return v;
		}
		c.version = b.get(6) << 8 | b.get(7);
		var n = u2(), p = new JPool(b, n);
		c.pool = p;
		var i = 1;
		while (i < n) {
			var tag = u1();
			p.tags[i] = tag;
			p.at[i] = at;
			switch tag {
				case 1: at += 2 + (b.get(at) << 8 | b.get(at + 1));
				case 3, 4, 9, 10, 11, 12, 17, 18: at += 4;
				case 5, 6:
					at += 8;
					i++;
				case 7, 8, 16, 19, 20: at += 2;
				case 15: at += 3;
				case t: throw 'class file: constant pool tag $t';
			}
			i++;
		}
		c.access = u2();
		c.name = p.cls(u2());
		var s = u2();
		c.superName = s == 0 ? null : p.cls(s);
		c.interfaces = [for (_ in 0...u2()) p.cls(u2())];
		function annotations(into:Array<String>, len:Int) {
			var end = at + len;
			for (_ in 0...u2()) {
				into.push(p.utf8(b.get(at) << 8 | b.get(at + 1)));
				at = skipAnnotation(b, at);
			}
			at = end;
		}
		function attributes(f:(String, Int) -> Bool) {
			for (_ in 0...u2()) {
				var name = p.utf8(u2()), len = u4(), end = at + len;
				if (!f(name, len)) at = end;
				at = end;
			}
		}
		for (_ in 0...u2()) {
			var f:JField = {access: u2(), name: p.utf8(u2()), desc: p.utf8(u2()), annotations: []};
			attributes((name, len) -> switch name {
				case "ConstantValue":
					f.value = p.value(u2());
					true;
				case "RuntimeVisibleAnnotations" | "RuntimeInvisibleAnnotations":
					annotations(f.annotations, len);
					true;
				case _: false;
			});
			c.fields.push(f);
		}
		for (_ in 0...u2()) {
			var m:JMethod = {access: u2(), name: p.utf8(u2()), desc: p.utf8(u2()), annotations: []};
			attributes((name, len) -> switch name {
				case "Code":
					m.code = code(c, b, at, len, m);
					true;
				case "RuntimeVisibleAnnotations" | "RuntimeInvisibleAnnotations":
					annotations(m.annotations, len);
					true;
				case _: false;
			});
			c.methods.push(m);
		}
		attributes((name, len) -> switch name {
			case "BootstrapMethods":
				for (_ in 0...u2()) {
					var h = p.handle(u2());
					c.bootstraps.push({method: h, args: [for (_ in 0...u2()) p.value(u2())]});
				}
				true;
			case "RuntimeVisibleAnnotations" | "RuntimeInvisibleAnnotations":
				annotations(c.annotations, len);
				true;
			case "InnerClasses":
				for (_ in 0...u2()) {
					var ic = u2(), oc = u2(), nm = u2(), acc = u2();
					c.inner.push({
						name: p.cls(ic),
						outer: oc == 0 ? null : p.cls(oc),
						simple: nm == 0 ? null : p.utf8(nm),
						access: acc
					});
				}
				true;
			case "NestHost":
				c.nestHost = p.cls(u2());
				true;
			case "EnclosingMethod":
				c.enclosing = p.cls(u2());
				true;
			case "NestMembers":
				c.nestMembers = [for (_ in 0...u2()) p.cls(u2())];
				true;
			case _: false;
		});
		return c;
	}

	// (an annotation's element values, skipped: only its type is kept)
	static function skipValue(b:Bytes, at:Int):Int {
		var tag = b.get(at++);
		return switch tag {
			case "e".code: at + 4;
			case "@".code: skipAnnotation(b, at);
			case "[".code:
				var n = b.get(at) << 8 | b.get(at + 1);
				at += 2;
				for (_ in 0...n)
					at = skipValue(b, at);
				at;
			case _: at + 2;
		}
	}

	static function skipAnnotation(b:Bytes, at:Int):Int {
		var n = b.get(at + 2) << 8 | b.get(at + 3);
		at += 4;
		for (_ in 0...n)
			at = skipValue(b, at + 2);
		return at;
	}

	static function code(c:ClassFile, b:Bytes, at:Int, len:Int, m:JMethod):JCode {
		inline function u2(o:Int)
			return b.get(o) << 8 | b.get(o + 1);
		inline function u4(o:Int)
			return b.get(o) << 24 | b.get(o + 1) << 16 | b.get(o + 2) << 8 | b.get(o + 3);
		var maxStack = u2(at), maxLocals = u2(at + 2), n = u4(at + 4);
		var code = b.sub(at + 8, n);
		var o = at + 8 + n, handlers = [];
		for (_ in 0...u2(o)) {
			var t = u2(o + 8);
			handlers.push({start: u2(o + 2), end: u2(o + 4), handler: u2(o + 6), type: t == 0 ? null : c.pool.cls(t)});
			o += 8;
		}
		o += 2;
		var frames:Null<Array<{pc:Int, locals:Array<String>, stack:Array<String>}>> = null;
		for (_ in 0...u2(o)) {
			var name = c.pool.utf8(u2(o + 2)), l = u4(o + 4);
			if (name == "StackMapTable") {
				// (the implicit first frame: the receiver, the parameters)
				var first = m.access & STATIC != 0 ? [] : [m.name == "<init>" && c.name != "java/lang/Object" ? "T" : Jvm.desc(c.name)];
				for (p in Jvm.signature(m.desc).params)
					first.push(Jvm.stackType(p));
				frames = stackMap(c, b, o + 10, u2(o + 8), first);
			}
			o += 6 + l;
		}
		return {maxStack: maxStack, maxLocals: maxLocals, code: code, handlers: handlers, frames: frames};
	}

	// StackMapTable's frames as lists of entries (a long or double one
	// entry; Jvm spreads them over two words), each from the one before,
	// the first from the method's descriptor
	static function stackMap(c:ClassFile, b:Bytes, at:Int, n:Int, first:Array<String>):Array<{pc:Int, locals:Array<String>, stack:Array<String>}> {
		inline function u2()
			return {
				var v = b.get(at) << 8 | b.get(at + 1);
				at += 2;
				v;
			};
		function vtype():String {
			var t = b.get(at++);
			return switch t {
				case 0: "X";
				case 1: "I";
				case 2: "F";
				case 3: "D";
				case 4: "J";
				case 5: "N";
				case 6: "T";
				case 7: Jvm.desc(c.pool.cls(u2()));
				case 8: "U" + u2();
				case _: throw 'StackMapTable: type $t';
			}
		}
		var frames = [], pc = -1, locals = first;
		for (_ in 0...n) {
			var t = b.get(at++), stack = [];
			var delta = if (t < 64) t else if (t < 128) {
				stack = [vtype()];
				t - 64;
			} else if (t == 247) {
				var d = u2();
				stack = [vtype()];
				d;
			} else if (t >= 248 && t <= 251) {
				var d = u2();
				if (t < 251) locals = locals.slice(0, locals.length - (251 - t));
				d;
			} else if (t >= 252 && t <= 254) {
				var d = u2();
				locals = locals.concat([for (_ in 0...t - 251) vtype()]);
				d;
			} else if (t == 255) {
				var d = u2();
				locals = [for (_ in 0...u2()) vtype()];
				stack = [for (_ in 0...u2()) vtype()];
				d;
			} else throw 'StackMapTable: frame type $t';
			pc = pc < 0 ? delta : pc + delta + 1;
			frames.push({pc: pc, locals: locals, stack: stack});
		}
		return frames;
	}
}

typedef JField = {access:Int, name:String, desc:String, ?value:JConst, annotations:Array<String>};
typedef JMethod = {access:Int, name:String, desc:String, ?code:JCode, annotations:Array<String>};

// a method's code: the bytecode, its exception table (catch types internal
// names, null for any), StackMapTable's frames (null: none, a class file
// before version 50's or a method without branches)
typedef JCode = {
	maxStack:Int,
	maxLocals:Int,
	code:Bytes,
	handlers:Array<{start:Int, end:Int, handler:Int, type:Null<String>}>,
	frames:Null<Array<{pc:Int, locals:Null<Array<String>>, stack:Array<String>}>>
};

// a field or method reference
typedef JRef = {owner:String, name:String, desc:String, ?iface:Bool};
// a method handle (kind: 1-4 fields, 5 virtual, 6 static, 7 special, 8 a constructor, 9 interface)
typedef JHandle = {kind:Int, owner:String, name:String, desc:String, iface:Bool};

enum JConst {
	CInt(v:Int);
	CFloat(bits:Int);
	CLong(hi:Int, lo:Int);
	CDouble(hi:Int, lo:Int);
	CString(s:String);
	// an internal name or an array's descriptor
	CClass(name:String);
	CMethodType(desc:String);
	CHandle(h:JHandle);
	CDynamic(bootstrap:Int, name:String, desc:String);
}

// the constant pool, its entries read on demand
class JPool {
	public final tags:Array<Int>;
	public final at:Array<Int>;

	final b:Bytes;
	final strings:Array<Null<String>>;

	public function new(b:Bytes, n:Int) {
		this.b = b;
		tags = [for (_ in 0...n) 0];
		at = [for (_ in 0...n) 0];
		strings = [for (_ in 0...n) null];
	}

	public inline function u2(o:Int)
		return b.get(o) << 8 | b.get(o + 1);

	inline function u4(o:Int)
		return b.get(o) << 24 | b.get(o + 1) << 16 | b.get(o + 2) << 8 | b.get(o + 3);

	public function utf8(i:Int):String {
		var s = strings[i];
		if (s != null) return s;
		if (tags[i] != 1) throw 'constant $i is not a string';
		var o = at[i], n = u2(o);
		s = mutf8(b, o + 2, n);
		strings[i] = s;
		return s;
	}

	public function cls(i:Int):String
		return utf8(u2(at[i]));

	public function ref(i:Int):JRef {
		var o = at[i], nt = at[u2(o + 2)];
		return {
			owner: cls(u2(o)),
			name: utf8(u2(nt)),
			desc: utf8(u2(nt + 2)),
			iface: tags[i] == 11
		};
	}

	public function handle(i:Int):JHandle {
		var o = at[i], r = ref(u2(o + 1));
		return {kind: b.get(o), owner: r.owner, name: r.name, desc: r.desc, iface: r.iface};
	}

	public function value(i:Int):JConst {
		var o = at[i];
		return switch tags[i] {
			case 3: CInt(u4(o));
			case 4: CFloat(u4(o));
			case 5: CLong(u4(o), u4(o + 4));
			case 6: CDouble(u4(o), u4(o + 4));
			case 8: CString(utf8(u2(o)));
			case 7: CClass(cls(i));
			case 16: CMethodType(utf8(u2(o)));
			case 15: CHandle(handle(i));
			case 17, 18:
				var nt = at[u2(o + 2)];
				CDynamic(u2(o), utf8(u2(nt)), utf8(u2(nt + 2)));
			case t: throw 'constant $i (tag $t) is not a value';
		}
	}

	// modified UTF-8 to Dex's form of a string (ClassFile's comment)
	public static function mutf8(b:Bytes, o:Int, n:Int):String {
		var ascii = true;
		for (k in o...o + n) {
			var c = b.get(k);
			if (c >= 0x80 || c < 2) {
				ascii = false;
				break;
			}
		}
		if (ascii) return b.getString(o, n);
		var s = new StringBuf(), k = o, end = o + n;
		while (k < end) {
			var c = b.get(k++), u;
			if (c < 0x80) u = c else if (c & 0xe0 == 0xc0) u = (c & 0x1f) << 6 | (b.get(k++) & 0x3f) else {
				u = (c & 0x0f) << 12 | (b.get(k) & 0x3f) << 6 | (b.get(k + 1) & 0x3f);
				k += 2;
			}
			if (u >= 2 && u < 0x80) s.addChar(u) else {
				s.addChar(1);
				s.add(StringTools.hex(u, 4));
			}
		}
		return s.toString();
	}
}
