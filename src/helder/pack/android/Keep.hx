package helder.pack.android;

import helder.pack.android.ClassFile;

using StringTools;

// ProGuard's keep rules, as far as Shrink needs them: -keep,
// -keepclassmembers and -keepclasseswithmembers with their class
// specification (annotation, access, class, interface, enum or
// @interface, names with ?, * and **, ! before any, extends or implements)
// and members (annotation, access, <init>, <fields>, <methods>, *, a type
// and a name, arguments with ... and ***). The rules that only keep names
// (-keepnames, -keepclassmembernames, allowshrinking) shrink nothing here
// (nothing is renamed) and are dropped, as are -if's conditional rules and
// the options that do not keep (-dontwarn, -assumenosideeffects, ...).
class Keep {
	// "keep" (the class and the members named), "members" (the members of a
	// kept class), "with" (the class and its members when it has them all)
	public final kind:String;
	final cls:ClassSpec;
	public final members:Array<MemberSpec>;

	function new(kind:String, cls:ClassSpec, members:Array<MemberSpec>) {
		this.kind = kind;
		this.cls = cls;
		this.members = members;
	}

	// what Android's default rules keep (AGP's proguard-android-optimize.txt:
	// enums' values and valueOf, Parcelable's CREATOR, @Keep's classes and members)
	public static final DEFAULTS = "
		-keepclassmembers enum * { public static **[] values(); public static ** valueOf(java.lang.String); }
		-keepclassmembers class * implements android.os.Parcelable { public static final ** CREATOR; }
		-keep @androidx.annotation.Keep class * { *; }
		-keepclasseswithmembers class * { @androidx.annotation.Keep <methods>; }
		-keepclasseswithmembers class * { @androidx.annotation.Keep <fields>; }
		-keepclasseswithmembers class * { @androidx.annotation.Keep <init>(...); }
	";

	public static function parse(text:String):Array<Keep> {
		var lines = [for (l in text.split("\n")) {
			var h = l.indexOf("#");
			h < 0 ? l : l.substr(0, h);
		}];
		var t = tokens(lines.join("\n")), at = 0, out = [];
		inline function peek()
			return at < t.length ? t[at] : "";
		function next()
			return at < t.length ? t[at++] : "";
		while (at < t.length) {
			var w = next();
			if (!w.startsWith("-")) continue;
			// (an -if rule's -keep belongs to it: both dropped)
			if (w == "-if") {
				skipSpec(t, at, i -> at = i);
				if (peek().startsWith("-keep")) {
					next();
					skipSpec(t, at, i -> at = i);
				}
				continue;
			}
			var kind = switch w {
				case "-keep": "keep";
				case "-keepclassmembers": "members";
				case "-keepclasseswithmembers": "with";
				case "-keepnames" | "-keepclassmembernames" | "-keepclasseswithmembernames": "names";
				case _: null;
			};
			if (kind == null) continue;
			var shrinks = false;
			while (peek() == ",") {
				next();
				if (next() == "allowshrinking") shrinks = true;
			}
			var start = at;
			var spec = try classSpec(t, at, i -> at = i) catch (e:String) {
				skipSpec(t, start, i -> at = i);
				continue;
			};
			if (kind == "names" || shrinks) continue;
			out.push(new Keep(kind, spec.cls, spec.members));
		}
		return out;
	}

	// a rule's specification skipped: to the next option
	static function skipSpec(t:Array<String>, at:Int, done:Int->Void) {
		var depth = 0;
		while (at < t.length && (depth > 0 || !t[at].startsWith("-") || t[at] == "-")) {
			if (t[at] == "{") depth++;
			if (t[at] == "}") depth--;
			at++;
		}
		done(at);
	}

	static function tokens(s:String):Array<String> {
		var out = [], k = 0;
		while (k < s.length) {
			var c = s.charAt(k);
			if (c == " " || c == "\t" || c == "\n" || c == "\r") {
				k++;
				continue;
			}
			if ("{}();,!".indexOf(c) >= 0) {
				out.push(c);
				k++;
				continue;
			}
			var e = k;
			while (e < s.length && " \t\n\r{}();,!".indexOf(s.charAt(e)) < 0)
				e++;
			out.push(s.substring(k, e));
			k = e;
		}
		return out;
	}

	static final ACCESS = [
		"public" => ClassFile.PUBLIC, "private" => ClassFile.PRIVATE, "protected" => ClassFile.PROTECTED, "static" => ClassFile.STATIC,
		"final" => ClassFile.FINAL, "abstract" => ClassFile.ABSTRACT, "native" => ClassFile.NATIVE, "synchronized" => ClassFile.SYNCHRONIZED,
		"volatile" => 0x40, "transient" => 0x80, "synthetic" => ClassFile.SYNTHETIC, "bridge" => ClassFile.BRIDGE, "varargs" => ClassFile.VARARGS
	];

	static function classSpec(t:Array<String>, at:Int, done:Int->Void):{cls:ClassSpec, members:Array<MemberSpec>} {
		var spec:ClassSpec = {names: [], set: 0, unset: 0};
		function next()
			return t[at++] ?? "";
		while (true) {
			var w = next();
			if (w.startsWith("@") && w.length > 1 && w != "@interface") {
				spec.annotation = w.substr(1);
				continue;
			}
			var neg = false;
			if (w == "!") {
				neg = true;
				w = next();
			}
			var a = ACCESS.get(w);
			if (a != null) {
				if (neg) spec.unset |= a else spec.set |= a;
				continue;
			}
			switch w {
				case "class":
					if (neg) spec.notKind = "class";
				case "interface" | "enum" | "@interface":
					if (neg) spec.notKind = w else spec.kind = w;
				case "@":
					spec.kind = "@" + next();
				case _:
					throw 'keep: a class specification at $w';
			}
			break;
		}
		while (true) {
			var neg = false, w = next();
			if (w == "!") {
				neg = true;
				w = next();
			}
			spec.names.push({pattern: w, neg: neg});
			if (t[at] == ",") at++ else break;
		}
		if (t[at] == "extends" || t[at] == "implements") {
			at++;
			var w = next();
			if (w.startsWith("@")) {
				spec.superAnnotation = w.substr(1);
				w = next();
			}
			spec.superName = w;
		}
		var members = [];
		if (t[at] == "{") {
			at++;
			while (at < t.length && t[at] != "}") {
				var m:MemberSpec = {set: 0, unset: 0, what: "*"};
				var words = [];
				while (at < t.length && t[at] != ";" && t[at] != "}") {
					var w = t[at++];
					if (w == "(") {
						var args = [];
						while (at < t.length && t[at] != ")") {
							if (t[at] != ",") args.push(t[at]);
							at++;
						}
						at++;
						m.args = args;
						continue;
					}
					words.push(w);
				}
				if (t[at] == ";") at++;
				var k = 0;
				while (k < words.length) {
					var w = words[k];
					if (w.startsWith("@") && w.length > 1) {
						m.annotation = w.substr(1);
						k++;
						continue;
					}
					var neg = w == "!";
					if (neg) w = words[++k];
					var a = ACCESS.get(w);
					if (a == null) break;
					if (neg) m.unset |= a else m.set |= a;
					k++;
				}
				var rest = words.slice(k);
				if (rest.length == 1) m.what = rest[0] else if (rest.length >= 2) {
					m.type = rest[0];
					m.what = rest[1];
				}
				members.push(m);
			}
			at++;
		}
		done(at);
		return {cls: spec, members: members};
	}

	// ---- matching

	// a Java name (a.b.C$D) against a pattern: ? one character but a dot,
	// * any but dots, ** any
	static final compiled = new Map<String, EReg>();

	public static function matches(pattern:String, name:String):Bool {
		if (pattern == "**" || pattern == "*" && name.indexOf(".") < 0) return true;
		if (pattern.indexOf("*") < 0 && pattern.indexOf("?") < 0) return pattern == name;
		var e = compiled.get(pattern);
		if (e != null) return e.match(name);
		var re = new StringBuf();
		re.add("^");
		var k = 0;
		while (k < pattern.length) {
			var c = pattern.charAt(k);
			if (c == "*") {
				if (pattern.charAt(k + 1) == "*") {
					re.add(".*");
					k += 2;
					continue;
				}
				re.add("[^.]*");
			} else if (c == "?") re.add("[^.]") else if ("\\^$.|+()[]{}".indexOf(c) >= 0) re.add("\\" + c) else re.add(c);
			k++;
		}
		re.add("$");
		compiled.set(pattern, e = new EReg(re.toString(), ""));
		return e.match(name);
	}

	public static function javaName(internal:String):String
		return internal.split("/").join(".");

	// a Java type (int, java.lang.String[], **) against a descriptor
	static function typeMatches(pattern:String, desc:String):Bool {
		if (pattern == "***") return true;
		var dims = 0;
		while (desc.charAt(dims) == "[")
			dims++;
		var pdims = 0, p = pattern;
		while (p.endsWith("[]")) {
			p = p.substr(0, p.length - 2);
			pdims++;
		}
		if (p == "%") return dims == pdims && desc.length == dims + 1;
		if (pdims != dims) return false;
		var base = desc.substr(dims);
		var prim = switch p {
			case "int": "I";
			case "long": "J";
			case "boolean": "Z";
			case "byte": "B";
			case "char": "C";
			case "short": "S";
			case "float": "F";
			case "double": "D";
			case "void": "V";
			case _: null;
		};
		if (prim != null) return base == prim;
		if (base.charAt(0) != "L") return false;
		return matches(p, javaName(base.substr(1, base.length - 2)));
	}

	static function hasAnnotation(list:Array<String>, pattern:String):Bool {
		for (a in list) if (matches(pattern, javaName(a.substr(1, a.length - 2)))) return true;
		return false;
	}

	// whether the rule's class specification names c (supers: its supertypes' internal names)
	public function classMatches(c:ClassFile, supers:Array<String>, find:String->Null<ClassFile>):Bool {
		var name = javaName(c.name), ok = false;
		for (n in cls.names) {
			// (a lone * is every class, packages and all)
			if (n.pattern == "*" || matches(n.pattern, name)) {
				if (n.neg) return false;
				ok = true;
			}
		}
		if (!ok) return false;
		if (cls.set & c.access != cls.set || cls.unset & c.access != 0) return false;
		var iface = c.access & ClassFile.INTERFACE != 0, isEnum = c.access & ClassFile.ENUM != 0,
			annotation = c.access & ClassFile.ANNOTATION != 0;
		switch cls.kind {
			case "interface": if (!iface) return false;
			case "enum": if (!isEnum) return false;
			case "@interface": if (!annotation) return false;
			case _:
		}
		switch cls.notKind {
			case "interface": if (iface) return false;
			case "class": if (!iface) return false;
			case "enum": if (isEnum) return false;
			case _:
		}
		if (cls.annotation != null && !hasAnnotation(c.annotations, cls.annotation)) return false;
		if (cls.superName != null) {
			var found = false;
			for (s in supers)
				if (s != c.name && matches(cls.superName, javaName(s))) {
					if (cls.superAnnotation != null) {
						var sc = find(s);
						if (sc == null || !hasAnnotation(sc.annotations, cls.superAnnotation)) continue;
					}
					found = true;
					break;
				}
			if (!found) return false;
		}
		return true;
	}

	static function memberMatches(m:MemberSpec, access:Int, name:String, desc:String, annotations:Array<String>, method:Bool):Bool {
		if (m.set & access != m.set || m.unset & access != 0) return false;
		if (m.annotation != null && !hasAnnotation(annotations, m.annotation)) return false;
		switch m.what {
			case "*" if (m.type == null): return true;
			case "<fields>": return !method;
			case "<methods>": return method && name != "<init>" && name != "<clinit>";
			case "<init>": if (!method || name != "<init>") return false;
			case w:
				if (w.indexOf("(") >= 0) return false;
				if (!matches(w, name)) return false;
				if (name == "<init>" || name == "<clinit>") return false;
				if (method != (m.args != null)) return false;
		}
		if (method && m.args != null) {
			var s = Jvm.signature(desc);
			if (m.type != null && m.what != "<init>" && !typeMatches(m.type, s.ret)) return false;
			if (!(m.args.length == 1 && m.args[0] == "...")) {
				if (m.args.length != s.params.length) return false;
				for (k in 0...s.params.length)
					if (m.args[k] != "..." && !typeMatches(m.args[k], s.params[k])) return false;
			}
		} else if (!method && m.type != null && !typeMatches(m.type, desc)) return false;
		return true;
	}

	public function fieldMatches(m:MemberSpec, f:JField):Bool
		return memberMatches(m, f.access, f.name, f.desc, f.annotations, false);

	public function methodMatches(m:MemberSpec, x:JMethod):Bool
		return memberMatches(m, x.access, x.name, x.desc, x.annotations, true);
}

typedef ClassSpec = {
	names:Array<{pattern:String, neg:Bool}>,
	set:Int,
	unset:Int,
	?kind:String,
	?notKind:String,
	?annotation:String,
	?superName:String,
	?superAnnotation:String
};

typedef MemberSpec = {
	set:Int,
	unset:Int,
	// *, <init>, <fields>, <methods> or a name
	what:String,
	?type:String,
	?args:Array<String>,
	?annotation:String
};
