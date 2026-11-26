import helder.dom.*;
import helder.dom.Tokenizer;
import haxe.DynamicAccess;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.dom against html5lib-tests' tokenizer tests and WPT's tree
// construction tests (bun run test dom-conformance, natively):
//
//   bin/dom/DomConformanceCheck [filter]      BLESS=1: manifest.json from the results
//
// Every case of the fixtures is listed in manifest.json; one without a
// status must pass, a pending one (its reason) must fail, a skipped one is
// not run (its reason: not applicable). A required case that fails, or a
// pending one that passes, fails the run. BLESS=1 writes the pending cases
// from the results instead (a reason kept while it still fails).
class DomConformanceCheck {
	static final HERE = "tests/dom";

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1";
		var only = Sys.args().length > 0 ? Sys.args()[0] : null;
		var manifest:Dynamic = haxe.Json.parse(File.getContent('$HERE/manifest.json'));
		need(manifest.schema == 1, "manifest: schema 1");
		var cases:Array<Dynamic> = manifest.cases;
		var results = new Map<String, Null<String>>();
		run(results);
		var seen = new Map<String, Bool>();
		var failures = [], fixed = [], blessed = [];
		var stats = new Map<String, Array<Int>>(), groups = [];
		for (c in cases) {
			var id:String = c.id;
			need(!seen.exists(id), 'manifest: $id twice');
			seen.set(id, true);
			need(results.exists(id), 'manifest: $id is no fixture case');
			var group = id.split("/")[0];
			if (!stats.exists(group)) {
				stats.set(group, [0, 0, 0, 0]);
				groups.push(group);
			}
			var st = stats[group];
			st[0]++;
			var out:Dynamic = {id: id};
			if (c.skip != null) {
				st[3]++;
				out.skip = c.skip;
				blessed.push(out);
				continue;
			}
			if (only != null && id.indexOf(only) < 0) {
				if (c.pending != null) out.pending = c.pending;
				blessed.push(out);
				continue;
			}
			var failure = results[id];
			if (failure == null) {
				st[1]++;
				if (c.pending != null) fixed.push('$id (pending: ${c.pending})');
			} else {
				st[2]++;
				out.pending = c.pending != null && c.pending != "new" ? c.pending : failure;
				if (c.pending == null) failures.push('$id: $failure');
			}
			blessed.push(out);
		}
		for (id in results.keys())
			need(seen.exists(id), '$id: not in the manifest');
		for (g in groups) {
			var s = stats[g];
			Sys.println('$g: ${s[1]} of ${s[0] - s[3]} pass, ${s[2]} pending, ${s[3]} skipped');
		}
		if (bless && only == null) {
			var text = File.getContent('$HERE/manifest.json');
			text = text.substr(0, text.indexOf('"cases": [') + 10);
			File.saveContent('$HERE/manifest.json', text + "\n" + [for (c in blessed) "\t\t" + haxe.Json.stringify(c)].join(",\n") + "\n\t]\n}\n");
			Sys.println("DomConformanceCheck: manifest.json written");
			return;
		}
		for (f in failures)
			Sys.println("FAIL " + f);
		for (f in fixed)
			Sys.println("FIXED " + f + " (BLESS=1 to require it)");
		if (failures.length + fixed.length > 0) {
			Sys.println('DomConformanceCheck: ${failures.length} required failing, ${fixed.length} pending passing');
			Sys.exit(1);
		}
		Sys.println("DomConformanceCheck: ok");
	}

	static function need(ok:Bool, what:String)
		if (!ok) throw "DomConformanceCheck: invalid " + what;

	// every case's result: null when it passes, else what differs
	static function run(results:Map<String, Null<String>>) {
		for (f in sorted('$HERE/fixtures/tokenizer'))
			tokenizerFile(f, results);
		for (f in sorted('$HERE/fixtures/tree-construction'))
			treeFile(f, results);
	}

	static function sorted(dir:String):Array<String> {
		var a = FileSystem.readDirectory(dir);
		a.sort(Reflect.compare);
		return a;
	}

	static function attempt(id:String, results:Map<String, Null<String>>, f:Void->Null<String>) {
		var r = try f() catch (e:Dynamic) "threw " + Std.string(e);
		results.set(id, r == null ? null : printable(r));
	}

	// (a reason as the manifest keeps it: one line, controls escaped, at most 200 characters)
	static function printable(s:String):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			var c = s.fastCodeAt(i);
			if (c < 0x20 || c == 0x7F || c >= 0xD800 && c <= 0xDFFF) b.add("\\u" + StringTools.hex(c, 4)) else b.addChar(c);
		}
		var t = b.toString();
		return t.length > 200 ? t.substr(0, 200) + "..." : t;
	}

	// --- tokenizer

	static function tokenizerFile(file:String, results:Map<String, Null<String>>) {
		var json:Dynamic = haxe.Json.parse(File.getContent('$HERE/fixtures/tokenizer/$file'));
		var tests:Array<Dynamic> = json.tests;
		for (i in 0...tests.length) {
			var t = tests[i];
			var states:Array<String> = t.initialStates ?? ["Data state"];
			for (s in states)
				attempt('tokenizer/$file#$i:${s.substr(0, s.length - 6)}', results, () -> tokenizerCase(t, s));
		}
	}

	static function unescape(s:String):String
		return ~/\\u([0-9A-Fa-f]{4})/g.map(s, r -> {
			var b = new StringBuf();
			b.addChar(Std.parseInt("0x" + r.matched(1)));
			b.toString();
		});

	static function tokenizerCase(t:Dynamic, state:String):Null<String> {
		var double = t.doubleEscaped == true;
		var input:String = t.input;
		if (double) input = unescape(input);
		var sink = new Tokens();
		var errors = [];
		var tok = new Tokenizer(input, sink, errors);
		tok.state = switch state {
			case "Data state": Tokenizer.DATA;
			case "PLAINTEXT state": Tokenizer.PLAINTEXT;
			case "RCDATA state": Tokenizer.RCDATA;
			case "RAWTEXT state": Tokenizer.RAWTEXT;
			case "Script data state": Tokenizer.SCRIPT_DATA;
			case "CDATA section state": Tokenizer.CDATA;
			case s: throw "state " + s;
		}
		tok.lastStartTag = t.lastStartTag;
		tok.run();
		var expected:Array<Dynamic> = t.output;
		var want = haxe.Json.stringify(normalize(expected, double));
		var got = haxe.Json.stringify(normalize(sink.out, false));
		if (want != got) return 'tokens $got, not $want';
		var wantErrors:Array<Dynamic> = t.errors ?? [];
		var w = [for (e in wantErrors) '${e.code}@${e.line}:${e.col}'].join(" ");
		var g = [for (e in errors) e.code + "@" + lineCol(input, e.offset)].join(" ");
		if (w != g) return 'errors $g, not $w';
		return null;
	}

	static function lineCol(s:String, offset:Int):String {
		var line = 1, col = 1, i = 0;
		while (i < offset && i < s.length) {
			var c = s.fastCodeAt(i++);
			if (c == "\n".code || c == "\r".code) {
				if (c == "\r".code && i < s.length && s.fastCodeAt(i) == "\n".code) i++;
				line++;
				col = 1;
			} else col++;
		}
		return '$line:$col';
	}

	// (adjacent character tokens as one; a start tag's attributes in their order)
	static function normalize(tokens:Array<Dynamic>, double:Bool):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		for (t in tokens) {
			var a:Array<Dynamic> = t;
			if (double) a = [for (x in a) Std.isOfType(x, String) ? unescape(x) : x];
			if (a[0] == "Character" && out.length > 0 && out[out.length - 1][0] == "Character") {
				out[out.length - 1] = ["Character", out[out.length - 1][1] + a[1]];
				continue;
			}
			if (a[0] == "StartTag") {
				var attrs:DynamicAccess<String> = a[2];
				var keys = attrs.keys();
				keys.sort(Reflect.compare);
				var pairs = [for (k in keys) [k, double ? unescape(attrs[k]) : attrs[k]]];
				a = ["StartTag", a[1], pairs, a.length > 3 && a[3] == true];
			}
			out.push(a);
		}
		return out;
	}

	// --- tree construction

	static final SECTIONS = ["#data", "#errors", "#new-errors", "#document-fragment", "#script-on", "#script-off", "#document", "#description"];

	// a .dat file's tests: each a map of its sections' lines (#data, or a #description before it, starts one)
	static function treeFile(file:String, results:Map<String, Null<String>>) {
		var lines = File.getContent('$HERE/fixtures/tree-construction/$file').split("\n");
		var tests = [], test:Null<Map<String, Array<String>>> = null, name = "";
		for (l in lines) {
			var header = SECTIONS.contains(l) && (test == null || name != "data" || l == "#errors");
			if (header && (l == "#description" || l == "#data" && (test == null || test.exists("document")))) {
				test = new Map();
				tests.push(test);
			}
			if (test == null) continue;
			if (header) {
				name = l.substr(1);
				test.set(name, []);
			} else test[name].push(l);
		}
		for (i in 0...tests.length)
			attempt('tree-construction/$file#$i', results, () -> treeCase(tests[i]));
	}

	static function treeCase(s:Map<String, Array<String>>):Null<String> {
		var data = s["data"].join("\n");
		var doc = s["document"];
		while (doc.length > 0 && doc[doc.length - 1] == "")
			doc.pop();
		var want = doc.join("\n");
		var got:String;
		if (s.exists("document-fragment")) {
			var ctx = s["document-fragment"][0].trim();
			var parts = ctx.split(" ");
			var host = Dom.parse("");
			var context = parts.length == 2 ? host.createElementNS(parts[0] == "svg" ? Namespaces.SVG : Namespaces.MATHML, parts[1]) : host.createElement(ctx);
			got = dump(Dom.parseFragment(data, context));
		} else got = dump(Dom.parse(data));
		if (got == want) return null;
		var g = got.split("\n"), w = want.split("\n"), k = 0;
		while (k < g.length && k < w.length && g[k] == w[k])
			k++;
		return 'differs at line ${k + 1}: ${g[k] ?? "(end)"}, not ${w[k] ?? "(end)"}';
	}

	// the tree in the tests' format: "| " and two spaces a level
	public static function dump(root:Node):String {
		var out = [];
		function walk(n:Node, depth:Int) {
			var pad = "| " + "".lpad(" ", depth * 2);
			switch n.nodeType {
				case Node.ELEMENT_NODE:
					var e:Element = cast n;
					var ns = switch e.namespaceURI {
						case Namespaces.SVG: "svg ";
						case Namespaces.MATHML: "math ";
						case _: "";
					}
					out.push(pad + "<" + ns + e.localName + ">");
					var attrs = [];
					for (a in e.attributes) {
						var name = switch a.namespaceURI {
							case Namespaces.XLINK: "xlink " + a.localName;
							case Namespaces.XML: "xml " + a.localName;
							case Namespaces.XMLNS: "xmlns " + a.localName;
							case _: a.localName;
						}
						attrs.push(name + "=\"" + a.value + "\"");
					}
					attrs.sort(Reflect.compare);
					for (a in attrs)
						out.push(pad + "  " + a);
					if (e is HTMLTemplateElement) {
						out.push(pad + "  content");
						var c = (cast e : HTMLTemplateElement).content.firstChild;
						while (c != null) {
							walk(c, depth + 2);
							c = c.nextSibling;
						}
					}
				case Node.TEXT_NODE:
					out.push(pad + "\"" + (cast n : Text).data + "\"");
				case Node.COMMENT_NODE:
					out.push(pad + "<!-- " + (cast n : Comment).data + " -->");
				case Node.PROCESSING_INSTRUCTION_NODE:
					var pi:ProcessingInstruction = cast n;
					out.push(pad + "<?" + pi.target + " " + pi.data + "?>");
				case Node.DOCUMENT_TYPE_NODE:
					var d:DocumentType = cast n;
					out.push(pad + "<!DOCTYPE " + d.name + (d.publicId != "" || d.systemId != "" ? ' "${d.publicId}" "${d.systemId}"' : "") + ">");
				case _:
			}
			var c = n.firstChild;
			while (c != null) {
				walk(c, depth + 1);
				c = c.nextSibling;
			}
		}
		var c = root.firstChild;
		while (c != null) {
			walk(c, 0);
			c = c.nextSibling;
		}
		return out.join("\n");
	}
}

// the tokenizer's tokens in the tests' format
class Tokens implements TokenSink {
	public var out:Array<Dynamic> = [];

	public function new() {}

	public function doctype(name:Null<String>, publicId:Null<String>, systemId:Null<String>, forceQuirks:Bool, start:Int, end:Int)
		out.push(["DOCTYPE", name, publicId, systemId, !forceQuirks]);

	public function tag(t:Tag) {
		if (t.end) {
			out.push(["EndTag", t.name]);
			return;
		}
		var attrs:DynamicAccess<String> = {};
		var a = t.attrs ?? [], i = 0;
		while (i < a.length) {
			attrs[a[i]] = a[i + 1];
			i += 2;
		}
		out.push(t.selfClosing ? ["StartTag", t.name, attrs, true] : ["StartTag", t.name, attrs]);
	}

	public function chars(text:String, start:Int, end:Int)
		out.push(["Character", text]);

	public function comment(data:String, start:Int, end:Int)
		out.push(["Comment", data]);

	public function pi(target:String, data:String, start:Int, end:Int)
		out.push(["ProcessingInstruction", target, data]);

	public function eof(at:Int) {}

	public function foreign():Bool
		return false;
}
