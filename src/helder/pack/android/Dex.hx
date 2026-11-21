package helder.pack.android;

import haxe.io.Bytes;

// A minimal DEX writer (Dalvik executable, version 035: what every Android
// runs), for the few Java classes an app needs as glue (Glue): classes
// with fields and methods whose code is given as Dalvik instructions
// (16-bit units) built against the file's pools (Refs: the index of a
// string, type, field or method, known once every class is collected).
// The layout the format specifies: the header, the id sections sorted as
// the runtime requires (strings by their UTF-16 units, types by their
// descriptor's string, protos by return type then parameters, fields and
// methods by class, name, then type or proto), the class definitions, then
// the data (type lists, code items, string data, class data) and the map
// of every section; the SHA-1 signature over everything after it, then the
// Adler-32 checksum. `check` reads a file back and verifies that structure
// (the checks: tests/pack). Grown here for Jvm's translated libraries:
// try items and their handlers, static values, strings beyond ASCII
// (ClassFile's escaped form, written as MUTF-8 and sorted by UTF-16 units),
// version 037 when an interface has code (default and static methods: API
// 24), classes ordered after their supertypes, and `split` for multidex.
// Ported from hxmc (hxmc.android.Dex), MIT.
class Dex {
	public static inline var PUBLIC = 0x1;
	public static inline var PRIVATE = 0x2;
	public static inline var PROTECTED = 0x4;
	public static inline var STATIC = 0x8;
	public static inline var FINAL = 0x10;
	public static inline var NATIVE = 0x100;
	public static inline var CONSTRUCTOR = 0x10000;

	static inline var NO_INDEX = -1;

	// the map's item types
	static inline var HEADER = 0x0000;
	static inline var STRING_ID = 0x0001;
	static inline var TYPE_ID = 0x0002;
	static inline var PROTO_ID = 0x0003;
	static inline var FIELD_ID = 0x0004;
	static inline var METHOD_ID = 0x0005;
	static inline var CLASS_DEF = 0x0006;
	static inline var MAP_LIST = 0x1000;
	static inline var TYPE_LIST = 0x1001;
	static inline var CLASS_DATA = 0x2000;
	static inline var CODE = 0x2001;
	static inline var STRING_DATA = 0x2002;
	static inline var ANNOTATION_SET = 0x1003;
	static inline var ANNOTATION = 0x2004;
	static inline var ANNOTATIONS_DIRECTORY = 0x2006;
	static inline var ENCODED_ARRAY = 0x2005;

	// the most ids of one kind a file indexes (16 bits)
	public static inline var LIMIT = 65536;

	// the classes in files under LIMIT's methods, fields and types each
	public static function split(classes:Array<DexClass>):Array<Array<DexClass>> {
		var files = [], cur = [], ms = new Map<String, Bool>(), fs = new Map<String, Bool>(), ts = new Map<String, Bool>();
		var nm = 0, nf = 0, nt = 0;
		for (c in classes) {
			var p = new Pools();
			p.collect(c);
			var am = [for (m in p.methods) m.cls + "->" + m.name + p.protoKey(m.ret, m.params)].filter(k -> !ms.exists(k));
			var af = [for (f in p.fields) f.cls + "->" + f.name + ":" + f.type].filter(k -> !fs.exists(k));
			var at = p.types.filter(k -> !ts.exists(k));
			if (cur.length > 0 && (nm + am.length > LIMIT || nf + af.length > LIMIT || nt + at.length > LIMIT)) {
				files.push(cur);
				cur = [];
				ms = new Map();
				fs = new Map();
				ts = new Map();
				nm = nf = nt = 0;
				p = new Pools();
				p.collect(c);
				am = [for (m in p.methods) m.cls + "->" + m.name + p.protoKey(m.ret, m.params)];
				af = [for (f in p.fields) f.cls + "->" + f.name + ":" + f.type];
				at = p.types;
			}
			for (k in am) ms.set(k, true);
			for (k in af) fs.set(k, true);
			for (k in at) ts.set(k, true);
			nm += am.length;
			nf += af.length;
			nt += at.length;
			cur.push(c);
		}
		if (cur.length > 0) files.push(cur);
		return files;
	}

	// a class after its superclass and interfaces of the same file (the format's rule)
	static function ordered(classes:Array<DexClass>):Array<DexClass> {
		var byName = [for (c in classes) c.name => c], done = new Map<String, Bool>(), out = [];
		function visit(c:DexClass) {
			if (done.exists(c.name)) return;
			done.set(c.name, true);
			for (s in [c.superName].concat(c.interfaces)) {
				var d = byName.get(s);
				if (d != null) visit(d);
			}
			out.push(c);
		}
		for (c in classes) visit(c);
		return out;
	}

	public static function write(classes:Array<DexClass>):Bytes {
		classes = ordered(classes);
		var pools = new Pools();
		// (collected: every name, then the code's references)
		for (c in classes)
			pools.collect(c);
		pools.sort();
		var defaults = false;
		for (c in classes)
			if (c.access & 0x200 != 0) for (m in c.methods)
				if (m.code != null && m.name != "<clinit>") defaults = true;
		var nS = pools.strings.length, nT = pools.types.length, nP = pools.protos.length, nF = pools.fields.length, nM = pools.methods.length,
			nC = classes.length;
		var at = 0x70;
		var stringIdsAt = at;
		at += 4 * nS;
		var typeIdsAt = at;
		at += 4 * nT;
		var protoIdsAt = at;
		at += 12 * nP;
		var fieldIdsAt = at;
		at += 8 * nF;
		var methodIdsAt = at;
		at += 8 * nM;
		var classDefsAt = at;
		at += 32 * nC;
		var dataAt = at;
		// the data, after the ids
		var data = new helder.pack.Buf(4096);
		inline function pos()
			return dataAt + data.len;
		inline function align4()
			while (data.len % 4 != 0)
				data.u8(0);
		// type lists (the protos' parameters, the classes' interfaces; one of each)
		var lists = new Map<String, Int>(), nLists = 0;
		var listsAt = pos();
		function typeList(types:Array<String>):Int {
			if (types.length == 0) return 0;
			var key = types.join(",");
			var o = lists.get(key);
			if (o != null) return o;
			align4();
			o = pos();
			data.u32(types.length);
			for (t in types)
				data.u16(pools.typeIndex(t));
			lists.set(key, o);
			nLists++;
			return o;
		}
		var protoParams = [for (p in pools.protos) typeList(p.params)];
		var interfaces = [for (c in classes) typeList(c.interfaces)];
		// code items
		align4();
		var codeAt = pos(), nCode = 0;
		var codeOffsets = new Map<String, Int>();
		for (c in classes)
			for (m in c.methods)
				if (m.code != null) {
					align4();
					codeOffsets.set(c.name + "->" + m.name + pools.protoKey(m.ret, m.params), pos());
					var insns = m.code.insns(pools);
					var tries = m.code.tries == null ? [] : m.code.tries(pools);
					data.u16(m.code.registers);
					data.u16(m.code.ins);
					data.u16(m.code.outs);
					data.u16(tries.length);
					data.u32(0); // debug info
					data.u32(insns.length);
					for (u in insns)
						data.u16(u);
					if (tries.length > 0) {
						if (insns.length % 2 == 1) data.u16(0);
						// (the handler lists after the items, each list once)
						var list = new helder.pack.Buf(64), offsets = new Map<String, Int>(), lists = [];
						for (t in tries) {
							var key = [for (h in t.handlers) h.type + "@" + h.addr].join(",") + "|" + t.all;
							if (!offsets.exists(key)) {
								offsets.set(key, -1);
								lists.push({key: key, t: t});
							}
						}
						var body = new helder.pack.Buf(64);
						body.uleb(lists.length);
						for (l in lists) {
							offsets.set(l.key, body.len);
							body.sleb(l.t.all == null ? l.t.handlers.length : -l.t.handlers.length);
							for (h in l.t.handlers) {
								body.uleb(pools.typeIndex(h.type));
								body.uleb(h.addr);
							}
							if (l.t.all != null) body.uleb(l.t.all);
						}
						for (t in tries) {
							data.u32(t.start);
							data.u16(t.count);
							data.u16(offsets.get([for (h in t.handlers) h.type + "@" + h.addr].join(",") + "|" + t.all));
						}
						data.buf(body);
					}
					nCode++;
				}
		// string data (MUTF-8, the length in UTF-16 units)
		var stringDataAt = pos();
		var stringOffsets = [];
		for (s in pools.strings) {
			stringOffsets.push(pos());
			if (s.indexOf("\x01") < 0) {
				data.uleb(s.length);
				data.str(s);
			} else {
				var u = units(s);
				data.uleb(u.length);
				for (c in u)
					if (c != 0 && c < 0x80) data.u8(c) else if (c < 0x800) {
						data.u8(0xc0 | c >> 6);
						data.u8(0x80 | (c & 0x3f));
					} else {
						data.u8(0xe0 | c >> 12);
						data.u8(0x80 | ((c >> 6) & 0x3f));
						data.u8(0x80 | (c & 0x3f));
					}
			}
			data.u8(0);
		}
		// class data: fields, then direct methods (static, private,
		// constructors) and virtual ones, each list by method index
		var classDataAt = pos();
		var classData = [];
		for (c in classes) {
			classData.push(pos());
			var statics = [for (f in c.fields) if (f.access & STATIC != 0) f], fields = [for (f in c.fields) if (f.access & STATIC == 0) f];
			var direct = [], virtual = [];
			for (m in c.methods)
				(m.access & (STATIC | PRIVATE | CONSTRUCTOR) != 0 ? direct : virtual).push(m);
			data.uleb(statics.length);
			data.uleb(fields.length);
			data.uleb(direct.length);
			data.uleb(virtual.length);
			for (list in [statics, fields]) {
				var idx = [for (f in list) {i: pools.fieldIndex(c.name, f.name, f.type), f: f}];
				idx.sort((a, b) -> a.i - b.i);
				var last = 0;
				for (e in idx) {
					data.uleb(e.i - last);
					data.uleb(e.f.access);
					last = e.i;
				}
			}
			for (list in [direct, virtual]) {
				var idx = [for (m in list) {i: pools.methodIndex(c.name, m.name, m.ret, m.params), m: m}];
				idx.sort((a, b) -> a.i - b.i);
				var last = 0;
				for (e in idx) {
					data.uleb(e.i - last);
					data.uleb(e.m.access);
					data.uleb(e.m.code == null ? 0 : codeOffsets.get(c.name + "->" + e.m.name + pools.protoKey(e.m.ret, e.m.params)));
					last = e.i;
				}
			}
		}
		// static values: the static fields' initial values in class data's
		// order, the trailing defaults left out
		var valuesAt = pos(), nValues = 0;
		var staticValues = [];
		for (c in classes) {
			var statics = [for (f in c.fields) if (f.access & STATIC != 0) f];
			statics.sort((a, b) -> pools.fieldIndex(c.name, a.name, a.type) - pools.fieldIndex(c.name, b.name, b.type));
			var n = statics.length;
			while (n > 0 && statics[n - 1].value == null)
				n--;
			if (n == 0) {
				staticValues.push(0);
				continue;
			}
			staticValues.push(pos());
			data.uleb(n);
			for (k in 0...n)
				encodeValue(data, pools, statics[k].value ?? defaultValue(statics[k].type), statics[k].type);
			nValues++;
		}
		// annotations: the classes' (with their elements: dalvik.annotation's
		// InnerClass, EnclosingClass) and methods' (types alone, runtime-visible:
		// @JavascriptInterface); an item per annotation, a set per list of them,
		// a directory per class that has any
		function classAnnotations(c:DexClass):Array<DexAnnotation>
			return c.annotations ?? [];
		function methodAnnotations(m:DexMethod):Array<DexAnnotation>
			return m.annotations == null ? [] : [for (t in m.annotations) {type: t, visibility: 1, elements: []}];
		inline function akey(a:DexAnnotation):String
			return a.type + "|" + a.visibility + "|" + [for (e in a.elements) e.name + "=" + valueKey(e.value)].join(",");
		var annotationAt = pos(), nAnnotations = 0;
		var annotationItems = new Map<String, Int>();
		function item(a:DexAnnotation) {
			var k = akey(a);
			if (annotationItems.exists(k)) return;
			annotationItems.set(k, pos());
			data.u8(a.visibility);
			data.uleb(pools.typeIndex(a.type));
			var els = a.elements.copy();
			els.sort((x, y) -> pools.stringIndex(x.name) - pools.stringIndex(y.name));
			data.uleb(els.length);
			for (e in els) {
				data.uleb(pools.stringIndex(e.name));
				encodeValue(data, pools, e.value, "I");
			}
			nAnnotations++;
		}
		for (c in classes) {
			for (a in classAnnotations(c))
				item(a);
			for (m in c.methods)
				for (a in methodAnnotations(m))
					item(a);
		}
		align4();
		var setAt = pos(), nSets = 0;
		var sets = new Map<String, Int>();
		function set(list:Array<DexAnnotation>):Int {
			var ts = list.copy();
			ts.sort((a, b) -> pools.typeIndex(a.type) - pools.typeIndex(b.type));
			var key = [for (a in ts) akey(a)].join(";");
			var o = sets.get(key);
			if (o != null) return o;
			o = pos();
			sets.set(key, o);
			data.u32(ts.length);
			for (a in ts)
				data.u32(annotationItems.get(akey(a)));
			nSets++;
			return o;
		}
		var classSets = [for (c in classes) classAnnotations(c).length > 0 ? set(classAnnotations(c)) : 0];
		var methodSets = [for (c in classes) [for (m in c.methods) methodAnnotations(m).length > 0 ? set(methodAnnotations(m)) : 0]];
		var directoryAt = pos(), nDirectories = 0;
		var directories = [];
		for (ci in 0...classes.length) {
			var c = classes[ci];
			var annotated = [for (k in 0...c.methods.length) if (methodSets[ci][k] != 0) {
				i: pools.methodIndex(c.name, c.methods[k].name, c.methods[k].ret, c.methods[k].params),
				off: methodSets[ci][k]
			}];
			if (annotated.length == 0 && classSets[ci] == 0) {
				directories.push(0);
				continue;
			}
			annotated.sort((a, b) -> a.i - b.i);
			directories.push(pos());
			data.u32(classSets[ci]);
			data.u32(0); // fields
			data.u32(annotated.length);
			data.u32(0); // parameters
			for (a in annotated) {
				data.u32(a.i);
				data.u32(a.off);
			}
			nDirectories++;
		}
		// the map
		align4();
		var mapAt = pos();
		var map = [
			[HEADER, 1, 0],
			[STRING_ID, nS, stringIdsAt],
			[TYPE_ID, nT, typeIdsAt],
			[PROTO_ID, nP, protoIdsAt],
			[FIELD_ID, nF, fieldIdsAt],
			[METHOD_ID, nM, methodIdsAt],
			[CLASS_DEF, nC, classDefsAt],
			[TYPE_LIST, nLists, listsAt],
			[CODE, nCode, codeAt],
			[STRING_DATA, nS, stringDataAt],
			[CLASS_DATA, nC, classDataAt],
			[ENCODED_ARRAY, nValues, valuesAt],
			[ANNOTATION, nAnnotations, annotationAt],
			[ANNOTATION_SET, nSets, setAt],
			[ANNOTATIONS_DIRECTORY, nDirectories, directoryAt],
			[MAP_LIST, 1, mapAt]
		].filter(e -> e[1] > 0);
		data.u32(map.length);
		for (e in map) {
			data.u16(e[0]);
			data.u16(0);
			data.u32(e[1]);
			data.u32(e[2]);
		}
		// the header and the ids
		var out = new helder.pack.Buf(dataAt + data.len);
		out.str(defaults ? "dex\n037\x00" : "dex\n035\x00");
		out.zeros(24); // checksum, signature
		out.u32(dataAt + data.len);
		out.u32(0x70);
		out.u32(0x12345678);
		out.u32(0); // link
		out.u32(0);
		out.u32(mapAt);
		for (s in [[nS, stringIdsAt], [nT, typeIdsAt], [nP, protoIdsAt], [nF, fieldIdsAt], [nM, methodIdsAt], [nC, classDefsAt]]) {
			out.u32(s[0]);
			out.u32(s[0] == 0 ? 0 : s[1]);
		}
		out.u32(data.len);
		out.u32(dataAt);
		for (o in stringOffsets)
			out.u32(o);
		for (t in pools.types)
			out.u32(pools.stringIndex(t));
		for (i in 0...nP) {
			var p = pools.protos[i];
			out.u32(pools.stringIndex(p.shorty));
			out.u32(pools.typeIndex(p.ret));
			out.u32(protoParams[i]);
		}
		for (f in pools.fields) {
			out.u16(pools.typeIndex(f.cls));
			out.u16(pools.typeIndex(f.type));
			out.u32(pools.stringIndex(f.name));
		}
		for (m in pools.methods) {
			out.u16(pools.typeIndex(m.cls));
			out.u16(pools.protoIndex(m.ret, m.params));
			out.u32(pools.stringIndex(m.name));
		}
		for (i in 0...nC) {
			var c = classes[i];
			out.u32(pools.typeIndex(c.name));
			out.u32(c.access);
			out.u32(pools.typeIndex(c.superName));
			out.u32(interfaces[i]);
			out.u32(NO_INDEX); // source file
			out.u32(directories[i]);
			out.u32(classData[i]);
			out.u32(staticValues[i]);
		}
		out.buf(data);
		var b = out.toBytes();
		b.blit(12, haxe.crypto.Sha1.make(b.sub(32, b.length - 32)), 0, 20);
		var a = new haxe.crypto.Adler32();
		a.update(b, 12, b.length - 12);
		b.setInt32(8, a.get());
		return b;
	}

	// a static field's initial value when none is given
	static function defaultValue(type:String):DexValue
		return switch type.charAt(0) {
			case "L" | "[": VNull;
			case "J": VLong(0, 0);
			case "D": VDouble(0, 0);
			case "F": VFloat(0);
			case _: VInt(0);
		}

	// an encoded_value (int-like ones as the field's type says)
	static function encodeValue(b:helder.pack.Buf, pools:Pools, v:DexValue, type:String) {
		function signed(t:Int, v:Int) {
			var n = 1;
			while (n < 4 && !(v >> (8 * n - 1) == 0 || v >> (8 * n - 1) == -1))
				n++;
			b.u8((n - 1) << 5 | t);
			for (k in 0...n)
				b.u8(v >> (8 * k));
		}
		function unsigned(t:Int, v:Int) {
			var n = 1;
			while (n < 4 && v >>> (8 * n) != 0)
				n++;
			b.u8((n - 1) << 5 | t);
			for (k in 0...n)
				b.u8(v >>> (8 * k));
		}
		// (a long's bytes, sign-extended: the fewest of eight)
		function long(t:Int, hi:Int, lo:Int, right:Bool) {
			var bytes = [for (k in 0...8) (k < 4 ? lo >>> (8 * k) : hi >>> (8 * (k - 4))) & 0xff];
			if (right) {
				var start = 0;
				while (start < 7 && bytes[start] == 0)
					start++;
				b.u8((7 - start) << 5 | t);
				for (k in start...8)
					b.u8(bytes[k]);
			} else {
				var n = 8;
				while (n > 1 && ((bytes[n - 1] == 0 && bytes[n - 2] & 0x80 == 0) || (bytes[n - 1] == 0xff && bytes[n - 2] & 0x80 != 0)))
					n--;
				b.u8((n - 1) << 5 | t);
				for (k in 0...n)
					b.u8(bytes[k]);
			}
		}
		switch v {
			case VNull: b.u8(0x1e);
			case VBool(x): b.u8((x ? 1 : 0) << 5 | 0x1f);
			case VArray(vs):
				b.u8(0x1c);
				b.uleb(vs.length);
				for (x in vs)
					encodeValue(b, pools, x, "I");
			case VString(s): unsigned(0x17, pools.stringIndex(s));
			case VType(d): unsigned(0x18, pools.typeIndex(d));
			case VLong(hi, lo): long(0x06, hi, lo, false);
			case VDouble(hi, lo): long(0x11, hi, lo, true);
			case VFloat(bits):
				var bytes = [for (k in 0...4) (bits >>> (8 * k)) & 0xff], start = 0;
				while (start < 3 && bytes[start] == 0)
					start++;
				b.u8((3 - start) << 5 | 0x10);
				for (k in start...4)
					b.u8(bytes[k]);
			case VInt(i):
				switch type {
					case "Z": b.u8((i != 0 ? 1 : 0) << 5 | 0x1f);
					case "B": signed(0x00, (i << 24) >> 24);
					case "S": signed(0x02, (i << 16) >> 16);
					case "C": unsigned(0x03, i & 0xffff);
					case _: signed(0x04, i);
				}
		}
	}

	static function valueKey(v:DexValue):String
		return switch v {
			case VInt(i): "i" + i;
			case VLong(h, l): "l" + h + ":" + l;
			case VFloat(x): "f" + x;
			case VDouble(h, l): "d" + h + ":" + l;
			case VString(x): "s" + x;
			case VType(d): "t" + d;
			case VNull: "n";
			case VBool(x): x ? "T" : "F";
			case VArray(vs): "[" + [for (x in vs) valueKey(x)].join(",") + "]";
		}

	// a string's UTF-16 units (ClassFile's escaped form read back)
	public static function units(s:String):Array<Int> {
		var out = [], k = 0;
		while (k < s.length) {
			var c = StringTools.fastCodeAt(s, k++);
			if (c == 1) {
				out.push(Std.parseInt("0x" + s.substr(k, 4)));
				k += 4;
			} else
				out.push(c);
		}
		return out;
	}

	// a string's MUTF-8 bytes up to its NUL, in ClassFile's form
	static function mutf8(b:Bytes, at:Int):String {
		var end = at;
		while (end < b.length && b.get(end) != 0)
			end++;
		return helder.pack.android.ClassFile.JPool.mutf8(b, at, end - at);
	}

	// strings in UTF-16 order, as the format sorts them
	public static function compare(a:String, b:String):Int {
		if (a.indexOf("\x01") < 0 && b.indexOf("\x01") < 0) return a < b ? -1 : a > b ? 1 : 0;
		var x = units(a), y = units(b), k = 0;
		while (k < x.length && k < y.length) {
			if (x[k] != y[k]) return x[k] - y[k];
			k++;
		}
		return x.length - y.length;
	}

	// ---- reading back

	// the file's structure verified (header, signature, checksum, the map,
	// the order and references of the ids, class data and code): the
	// problems found (none: empty); classes gets "Lname; method(params)ret" lines
	public static function check(b:Bytes, ?classes:Array<String>):Array<String> {
		var errors = [];
		function err(s:String)
			errors.push(s);
		if (b.length < 0x70 || b.getString(0, 4) != "dex\n") return ["not a DEX file"];
		if (["035", "037", "038", "039"].indexOf(b.getString(4, 3)) < 0) return ["version " + b.getString(4, 3)];
		var u32 = b.getInt32, u16 = b.getUInt16;
		if (u32(32) != b.length) err("file_size " + u32(32) + " is not the file's " + b.length);
		if (u32(36) != 0x70) err("header_size");
		if (u32(40) != 0x12345678) err("endian_tag");
		var a = new haxe.crypto.Adler32();
		a.update(b, 12, b.length - 12);
		if (a.get() != u32(8)) err("checksum");
		if (haxe.crypto.Sha1.make(b.sub(32, b.length - 32)).compare(b.sub(12, 20)) != 0) err("signature");
		var nS = u32(56), sAt = u32(60), nT = u32(64), tAt = u32(68), nP = u32(72), pAt = u32(76), nF = u32(80), fAt = u32(84), nM = u32(88),
			mAt = u32(92), nC = u32(96), cAt = u32(100), dataSize = u32(104), dataAt = u32(108);
		if (dataAt + dataSize != b.length) err("the data section does not end the file");
		if (dataAt % 4 != 0 || dataSize % 4 != 0) err("the data section is not aligned");
		function uleb(at:Array<Int>):Int {
			var v = 0, shift = 0, c;
			do {
				c = b.get(at[0]++);
				v |= (c & 0x7f) << shift;
				shift += 7;
			} while (c & 0x80 != 0);
			return v;
		}
		// the map: sections in order, each where the header says
		var map = u32(52), n = u32(map), last = -1, seen = new Map<Int, Array<Int>>();
		for (i in 0...n) {
			var e = map + 4 + 12 * i, type = u16(e), count = u32(e + 4), off = u32(e + 8);
			if (off <= last) err("map: section 0x" + StringTools.hex(type) + " out of order");
			if (off >= b.length) err("map: section 0x" + StringTools.hex(type) + " outside the file");
			last = off;
			seen.set(type, [count, off]);
		}
		for (s in [[HEADER, 1, 0], [STRING_ID, nS, sAt], [TYPE_ID, nT, tAt], [PROTO_ID, nP, pAt], [FIELD_ID, nF, fAt], [METHOD_ID, nM, mAt], [CLASS_DEF, nC, cAt],
			[MAP_LIST, 1, map]])
			if (s[1] > 0) {
				var m = seen.get(s[0]);
				if (m == null || m[0] != s[1] || m[1] != s[2]) err("map: section 0x" + StringTools.hex(s[0]) + " is not the header's");
			}
		if (map % 4 != 0) err("map: not aligned");
		// strings, sorted; types sorted and naming strings
		var strings = [];
		for (i in 0...nS) {
			var at = [u32(sAt + 4 * i)];
			if (at[0] < dataAt) err("string " + i + " outside the data");
			uleb(at);
			var s = mutf8(b, at[0]);
			if (i > 0 && !(compare(strings[i - 1], s) < 0)) err("strings out of order at " + i);
			strings.push(s);
		}
		function str(i:Int):String {
			if (i >= 0 && i < nS) return strings[i];
			err("a string index " + i);
			return "?";
		}
		var types = [for (i in 0...nT) u32(tAt + 4 * i)];
		for (i in 1...nT)
			if (types[i] <= types[i - 1]) err("types out of order at " + i);
		function type(i:Int):String {
			if (i >= 0 && i < nT) return str(types[i]);
			err("a type index " + i);
			return "?";
		}
		function list(off:Int):Array<Int> {
			if (off == 0) return [];
			if (off % 4 != 0) err("a type list not aligned");
			return [for (k in 0...u32(off)) u16(off + 4 + 2 * k)];
		}
		var protos = [];
		for (i in 0...nP) {
			var at = pAt + 12 * i, ret = u32(at + 4), params = list(u32(at + 8));
			var shorty = [for (t in [ret].concat(params)) {var d = type(t); d.charAt(0) == "[" ? "L" : d.charAt(0);}].join("");
			if (str(u32(at)) != shorty) err("proto " + i + ": shorty " + str(u32(at)) + ", not " + shorty);
			var key = [ret].concat(params);
			if (i > 0) {
				var prev = protos[i - 1], c = 0;
				c = prev[0] - key[0];
				var k = 1;
				while (c == 0 && k < prev.length && k < key.length) {
					c = prev[k] - key[k];
					k++;
				}
				if (c == 0) c = prev.length - key.length;
				if (c >= 0) err("protos out of order at " + i);
			}
			protos.push(key);
		}
		function protoString(p:Int)
			return "(" + [for (k in 1...protos[p].length) type(protos[p][k])].join("") + ")" + type(protos[p][0]);
		var prev = [-1, -1, -1];
		for (i in 0...nF) {
			var at = fAt + 8 * i, k = [u16(at), u32(at + 4), u16(at + 2)];
			if (k[0] < prev[0] || (k[0] == prev[0] && (k[1] < prev[1] || (k[1] == prev[1] && k[2] <= prev[2])))) err("fields out of order at " + i);
			type(k[0]);
			type(k[2]);
			str(k[1]);
			prev = k;
		}
		prev = [-1, -1, -1];
		var methods = [];
		for (i in 0...nM) {
			var at = mAt + 8 * i, k = [u16(at), u32(at + 4), u16(at + 2)];
			if (k[0] < prev[0] || (k[0] == prev[0] && (k[1] < prev[1] || (k[1] == prev[1] && k[2] <= prev[2])))) err("methods out of order at " + i);
			if (k[2] >= nP) err("method " + i + ": a proto index");
			methods.push(k);
			prev = k;
		}
		// classes: their data, the code of each method
		for (i in 0...nC) {
			var at = cAt + 32 * i, name = type(u32(at));
			type(u32(at + 8));
			for (t in list(u32(at + 12)))
				type(t);
			var cd = u32(at + 24);
			if (cd == 0) continue;
			var p = [cd];
			var counts = [for (_ in 0...4) uleb(p)];
			for (k in 0...2) {
				var idx = 0;
				for (j in 0...counts[k]) {
					var d = uleb(p);
					if (j > 0 && d == 0) err(name + ": fields out of order");
					idx += d;
					uleb(p);
				}
			}
			for (k in 2...4) {
				var idx = 0;
				for (j in 0...counts[k]) {
					var d = uleb(p);
					if (j > 0 && d == 0) err(name + ": methods out of order");
					idx += d;
					var access = uleb(p), code = uleb(p);
					if (idx >= nM) {
						err(name + ": a method index");
						continue;
					}
					var m = methods[idx];
					if (type(m[0]) != name) err(name + ": method " + str(m[1]) + " of another class");
					var sig = str(m[1]) + protoString(m[2]);
					if (classes != null) classes.push(name + " " + sig);
					if (k == 2 && access & (STATIC | PRIVATE | CONSTRUCTOR) == 0) err(name + "." + sig + ": a virtual method among the direct ones");
					if (k == 3 && access & (STATIC | PRIVATE | CONSTRUCTOR) != 0) err(name + "." + sig + ": a direct method among the virtual ones");
					if ((code == 0) != (access & (NATIVE | 0x400) != 0)) err(name + "." + sig + ": code and flags disagree");
					if (code != 0) {
						if (code % 4 != 0 || code < dataAt) err(name + "." + sig + ": its code is not aligned in the data");
						var ins = (access & STATIC != 0 ? 0 : 1);
						for (t in 1...protos[m[2]].length) {
							var d = type(protos[m[2]][t]);
							ins += d == "J" || d == "D" ? 2 : 1;
						}
						if (u16(code + 2) != ins) err(name + "." + sig + ": ins_size " + u16(code + 2) + ", not " + ins);
						if (u16(code) < ins) err(name + "." + sig + ": fewer registers than ins");
						var n = u32(code + 12), tries = u16(code + 6);
						if (code + 16 + 2 * n > b.length) err(name + "." + sig + ": its code outside the file");
						if (tries > 0) {
							var t = code + 16 + 2 * n + (n % 2 == 1 ? 2 : 0), handlers = t + 8 * tries, last = 0;
							var count = [handlers];
							var lists = uleb(count), offs = new Map<Int, Bool>();
							for (_ in 0...lists) {
								offs.set(count[0] - handlers, true);
								var sz = 0, v = 0, shift = 0, c;
								// (sleb128)
								do {
									c = b.get(count[0]++);
									v |= (c & 0x7f) << shift;
									shift += 7;
								} while (c & 0x80 != 0);
								sz = shift < 32 && c & 0x40 != 0 ? v | (-1 << shift) : v;
								for (_ in 0...(sz < 0 ? -sz : sz)) {
									type(uleb(count));
									if (uleb(count) >= n) err(name + "." + sig + ": a handler outside its code");
								}
								if (sz <= 0 && uleb(count) >= n) err(name + "." + sig + ": a catch-all outside its code");
							}
							for (k in 0...tries) {
								var start = u32(t + 8 * k), cnt = u16(t + 8 * k + 4), off = u16(t + 8 * k + 6);
								if (start < last || start + cnt > n) err(name + "." + sig + ": try " + k + " out of order or outside its code");
								if (!offs.exists(off)) err(name + "." + sig + ": try " + k + "'s handlers");
								last = start + cnt;
							}
						}
					}
				}
			}
		}
		return errors;
	}
}

typedef DexClass = {
	name:String,
	access:Int,
	superName:String,
	interfaces:Array<String>,
	// (a static field's value: its initial one, static values')
	fields:Array<{name:String, type:String, access:Int, ?value:DexValue}>,
	methods:Array<DexMethod>,
	?annotations:Array<DexAnnotation>
};

enum DexValue {
	VInt(v:Int);
	VLong(hi:Int, lo:Int);
	VFloat(bits:Int);
	VDouble(hi:Int, lo:Int);
	VString(s:String);
	VType(desc:String);
	VNull;
	VBool(v:Bool);
	VArray(values:Array<DexValue>);
}

// an annotation (visibility: 0 build, 1 runtime, 2 system) and its elements
typedef DexAnnotation = {type:String, visibility:Int, elements:Array<{name:String, value:DexValue}>};

// a try item: its range in code units, the handlers' types (descriptors)
// and addresses in order, the catch-all's address
typedef DexTry = {start:Int, count:Int, handlers:Array<{type:String, addr:Int}>, ?all:Int};

typedef DexMethod = {
	name:String,
	ret:String,
	params:Array<String>,
	access:Int,
	?code:DexCode,
	// its annotations' types (runtime-visible, no elements: Landroid/webkit/JavascriptInterface;)
	?annotations:Array<String>
};

// a method's code: its registers (the arguments are the last `ins`), the
// most argument words a call in it passes, the instructions, its try
// items (called after insns with the same pools)
typedef DexCode = {registers:Int, ins:Int, outs:Int, insns:Refs->Array<Int>, ?tries:Refs->Array<DexTry>};

// the indices of the file's pools, for the instructions
interface Refs {
	function type(desc:String):Int;
	function string(s:String):Int;
	function field(cls:String, name:String, type:String):Int;
	function method(cls:String, name:String, ret:String, params:Array<String>):Int;
}

// what the classes name: added while collecting (indices 0 then), sorted once
private class Pools implements Refs {
	public var strings:Array<String> = [];
	public var types:Array<String> = [];
	public var protos:Array<{ret:String, params:Array<String>, shorty:String}> = [];
	public var fields:Array<{cls:String, name:String, type:String}> = [];
	public var methods:Array<{cls:String, name:String, ret:String, params:Array<String>}> = [];

	final stringIdx = new Map<String, Int>();
	final typeIdx = new Map<String, Int>();
	final protoIdx = new Map<String, Int>();
	final fieldIdx = new Map<String, Int>();
	final methodIdx = new Map<String, Int>();
	var sorted = false;

	public function new() {}

	// every name of a class, then its code's references
	public function collect(c:DexClass) {
		type(c.name);
		type(c.superName);
		for (i in c.interfaces)
			type(i);
		for (f in c.fields) {
			field(c.name, f.name, f.type);
			if (f.value != null) value(f.value);
		}
		if (c.annotations != null)
			for (a in c.annotations) {
				type(a.type);
				for (e in a.elements) {
					string(e.name);
					value(e.value);
				}
			}
		for (m in c.methods) {
			method(c.name, m.name, m.ret, m.params);
			if (m.annotations != null)
				for (t in m.annotations)
					type(t);
			if (m.code != null) {
				m.code.insns(this);
				if (m.code.tries != null) for (t in m.code.tries(this))
					for (h in t.handlers)
						type(h.type);
			}
		}
	}

	function value(v:DexValue)
		switch v {
			case VString(s): string(s);
			case VType(d): type(d);
			case VArray(vs): for (x in vs) value(x);
			case _:
		}

	public function string(s:String):Int {
		if (!sorted && !stringIdx.exists(s)) {
			stringIdx.set(s, -1);
			strings.push(s);
		}
		return stringIndex(s);
	}

	public function type(d:String):Int {
		if (!sorted && !typeIdx.exists(d)) {
			typeIdx.set(d, -1);
			types.push(d);
			string(d);
		}
		return typeIndex(d);
	}

	public function protoKey(ret:String, params:Array<String>):String
		return "(" + params.join("") + ")" + ret;

	function proto(ret:String, params:Array<String>) {
		var k = protoKey(ret, params);
		if (sorted || protoIdx.exists(k)) return;
		protoIdx.set(k, -1);
		var shorty = [for (t in [ret].concat(params)) t.charAt(0) == "[" ? "L" : t.charAt(0)].join("");
		protos.push({ret: ret, params: params, shorty: shorty});
		string(shorty);
		type(ret);
		for (p in params)
			type(p);
	}

	public function field(cls:String, name:String, t:String):Int {
		var k = cls + "->" + name + ":" + t;
		if (!sorted && !fieldIdx.exists(k)) {
			fieldIdx.set(k, -1);
			fields.push({cls: cls, name: name, type: t});
			type(cls);
			type(t);
			string(name);
		}
		return fieldIndex(cls, name, t);
	}

	public function method(cls:String, name:String, ret:String, params:Array<String>):Int {
		var k = cls + "->" + name + protoKey(ret, params);
		if (!sorted && !methodIdx.exists(k)) {
			methodIdx.set(k, -1);
			methods.push({cls: cls, name: name, ret: ret, params: params});
			type(cls);
			string(name);
			proto(ret, params);
		}
		return methodIndex(cls, name, ret, params);
	}

	public function stringIndex(s:String):Int
		return sorted ? stringIdx.get(s) : 0;

	public function typeIndex(d:String):Int
		return sorted ? typeIdx.get(d) : 0;

	public function protoIndex(ret:String, params:Array<String>):Int
		return sorted ? protoIdx.get(protoKey(ret, params)) : 0;

	public function fieldIndex(cls:String, name:String, t:String):Int
		return sorted ? fieldIdx.get(cls + "->" + name + ":" + t) : 0;

	public function methodIndex(cls:String, name:String, ret:String, params:Array<String>):Int
		return sorted ? methodIdx.get(cls + "->" + name + protoKey(ret, params)) : 0;

	static function cmp(a:Int, b:Int):Int
		return a < b ? -1 : a > b ? 1 : 0;

	public function sort() {
		strings.sort(Dex.compare);
		for (i in 0...strings.length)
			stringIdx.set(strings[i], i);
		sorted = true;
		types.sort((a, b) -> cmp(stringIndex(a), stringIndex(b)));
		for (i in 0...types.length)
			typeIdx.set(types[i], i);
		protos.sort((a, b) -> {
			var c = cmp(typeIndex(a.ret), typeIndex(b.ret)), k = 0;
			while (c == 0 && k < a.params.length && k < b.params.length) {
				c = cmp(typeIndex(a.params[k]), typeIndex(b.params[k]));
				k++;
			}
			c != 0 ? c : cmp(a.params.length, b.params.length);
		});
		for (i in 0...protos.length)
			protoIdx.set(protoKey(protos[i].ret, protos[i].params), i);
		fields.sort((a, b) -> {
			var c = cmp(typeIndex(a.cls), typeIndex(b.cls));
			if (c == 0) c = cmp(stringIndex(a.name), stringIndex(b.name));
			c != 0 ? c : cmp(typeIndex(a.type), typeIndex(b.type));
		});
		for (i in 0...fields.length)
			fieldIdx.set(fields[i].cls + "->" + fields[i].name + ":" + fields[i].type, i);
		methods.sort((a, b) -> {
			var c = cmp(typeIndex(a.cls), typeIndex(b.cls));
			if (c == 0) c = cmp(stringIndex(a.name), stringIndex(b.name));
			c != 0 ? c : cmp(protoIndex(a.ret, a.params), protoIndex(b.ret, b.params));
		});
		for (i in 0...methods.length)
			methodIdx.set(methods[i].cls + "->" + methods[i].name + protoKey(methods[i].ret, methods[i].params), i);
	}
}
