import haxe.Json;
import haxe.io.Bytes;
import helder.css.Css;
import helder.css.CssAnB;
import helder.css.CssDeclaration;
import helder.css.CssRule;
import helder.css.CssValue;
import helder.css.Parser;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.css against css-parsing-tests (fixtures/css-parsing-tests):
// each case of manifest.json run through its file's entry point, our
// result in the fixtures' JSON form against the expected one. That one
// is upstream's, less the parse errors it lists (["error", "invalid"],
// "eof-in-string", "eof-in-url": this parser returns nothing for an
// invalid construct and reports no errors), or the case's own
// "expected" where the current Editor's Draft reads it otherwise than
// the 2021 draft the fixtures follow ("why" says how); "ranges": the
// case tokenized with unicode ranges allowed (the ED tokenizes
// unicode-range tokens for the unicode-range descriptor alone).
//
// Required cases must pass; a pending one ("pending": why) must fail, and
// passing fails the run until BLESS=1 requires it. BLESS=1 writes the
// manifest's pending cases from the results; DUMP=1 prints each result,
// SHOW=1 each one that differs, pending or not.
class CssConformanceCheck {
	static final DIR = "tests/css/fixtures/css-parsing-tests";

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1", dump = Sys.getEnv("DUMP") == "1", show = Sys.getEnv("SHOW") == "1";
		var manifest:Dynamic = Json.parse(File.getContent("tests/css/manifest.json"));
		var cases:Array<Dynamic> = manifest.cases;
		var byFile = new Map<String, Array<Dynamic>>();
		for (c in cases) {
			if (!byFile.exists(c.file)) byFile.set(c.file, []);
			byFile.get(c.file).push(c);
		}
		var failures = [], fixed = [], stats = [];
		var files = FileSystem.readDirectory(DIR).filter(f -> f.endsWith(".json"));
		files.sort(Reflect.compare);
		for (f in files) {
			var pairs:Array<Dynamic> = Json.parse(File.getContent('$DIR/$f'));
			var listed = byFile.get(f) ?? [];
			if (listed.length != pairs.length >> 1) failures.push('$f: ${pairs.length >> 1} cases, the manifest lists ${listed.length} (node tests/css/import-css-parsing-tests.mjs)');
			var pass = 0;
			for (c in listed) {
				var index:Int = c.index;
				var input:Dynamic = pairs[index * 2];
				if ((Std.isOfType(input, String) ? input : input.css_bytes) != c.input) {
					failures.push('$f#${c.index}: the manifest\'s input is not the fixture\'s');
					continue;
				}
				var expected:Dynamic = c.expected != null ? c.expected : normalize(pairs[index * 2 + 1], f);
				var actual:Dynamic = try run(f, input, c.ranges == true) catch (e:Dynamic) ["threw", Std.string(e)];
				if (dump) Sys.println('$f#${c.index} ${json(c.input)}\n  ${json(actual)}');
				var ok = same(actual, expected);
				if (ok) pass++;
				var id = '$f#${c.index} ${json(c.input)}';
				if (ok && c.pending != null) {
					fixed.push('$id passes now (pending: ${c.pending})');
					if (bless) Reflect.deleteField(c, "pending");
				} else if (!ok && show) {
					Sys.println('$f#${c.index} ${json(c.input)}\n    expected ${json(expected)}\n    actual   ${json(actual)}');
				}
				if (!ok && c.pending == null) {
					var why = 'expected ${json(expected)}\n    actual   ${json(actual)}';
					failures.push('$id\n    $why');
					if (bless) c.pending = "differs";
				}
			}
			stats.push('$f: $pass of ${listed.length} pass');
		}
		for (s in stats)
			Sys.println(s);
		if (bless) {
			// (as the import writes it: its fields in order, a case a line)
			var files:haxe.DynamicAccess<Dynamic> = manifest.files, names = [for (k in files.keys()) k];
			names.sort(Reflect.compare);
			var skips = [for (f in names) '\t\t${json(f)}: {\n\t\t\t"skip": ${json(files[f].skip)}\n\t\t}'];
			var head = '{\n\t"schema": ${manifest.schema},\n\t"repository": ${json(manifest.repository)},\n\t"revision": ${json(manifest.revision)},\n\t"license": ${json(manifest.license)},\n\t"files": {\n'
				+ skips.join(",\n") + '\n\t},\n\t"cases": [\n';
			File.saveContent("tests/css/manifest.json", head + [for (c in cases) "\t\t" + line(c)].join(",\n") + "\n\t]\n}\n");
			Sys.println("BLESS: tests/css/manifest.json written");
			return;
		}
		for (f in failures)
			Sys.println("FAIL " + f);
		for (f in fixed)
			Sys.println("FIXED " + f + " (BLESS=1 to require it)");
		if (failures.length + fixed.length > 0) {
			Sys.println('CssConformanceCheck: ${failures.length} required failing, ${fixed.length} pending passing');
			Sys.exit(1);
		}
		Sys.println("CssConformanceCheck: all pass");
	}

	// (a case's fields in the import's order, then the manifest's own)
	static function line(c:Dynamic):String {
		var parts = ['"file":${json(c.file)}', '"index":${c.index}', '"input":${json(c.input)}'];
		for (k in ["pending", "ranges", "why", "expected"])
			if (Reflect.hasField(c, k)) parts.push('"$k":${json(Reflect.field(c, k))}');
		return "{" + parts.join(",") + "}";
	}

	// (JSON as node writes it: Eval's Json.stringify leaves control characters as they are)
	static function json(v:Dynamic):String {
		if (v == null) return "null";
		if (Std.isOfType(v, String)) {
			var b = new StringBuf();
			b.add('"');
			var s:String = v;
			for (k in 0...s.length) {
				var c = s.charCodeAt(k);
				if (c == '"'.code || c == "\\".code) {
					b.add("\\");
					b.addChar(c);
				} else if (c < 0x20) b.add(switch c {
					case 8: "\\b";
					case 9: "\\t";
					case 10: "\\n";
					case 12: "\\f";
					case 13: "\\r";
					default: "\\u" + StringTools.hex(c, 4).toLowerCase();
				}) else b.addChar(c);
			}
			b.add('"');
			return b.toString();
		}
		if (Std.isOfType(v, Array)) return "[" + [for (x in (v : Array<Dynamic>)) json(x)].join(",") + "]";
		return Std.string(v);
	}

	static function run(file:String, input:Dynamic, ranges:Bool):Dynamic
		return switch file {
			case "component_value_list.json": values(new Parser(input, Css.tokens(input, ranges)).values(Parser.NONE, false, false));
			case "one_component_value.json": orError(Css.value(input), value);
			case "declaration_list.json": [for (d in Css.declarations(input)) declaration(d)];
			case "blocks_contents.json": items(Css.block(input));
			case "one_declaration.json": orError(Css.declaration(input), declaration);
			case "one_rule.json": orError(Css.rule(input), rule);
			case "rule_list.json" | "stylesheet.json": items(Css.sheet(input));
			case "stylesheet_bytes.json":
				var s:String = input.css_bytes, b = Bytes.alloc(s.length);
				for (k in 0...s.length)
					b.set(k, s.charCodeAt(k));
				var d = Css.decode(b, input.protocol_encoding, input.environment_encoding);
				[items(Css.sheet(d.text)), d.encoding];
			case "An+B.json":
				var r = CssAnB.parse(Css.values(input));
				r == null ? null : [r.a, r.b];
			default: throw 'no entry point for $file';
		}

	static function orError<T>(v:Null<T>, f:T->Dynamic):Dynamic
		return v == null ? ["error"] : f(v);

	// (upstream's expected: its parse errors out of lists; a single result's error any error)
	static function normalize(e:Dynamic, file:String):Dynamic {
		if (file.startsWith("one_") && isError(e)) return ["error"];
		if (file == "stylesheet_bytes.json") return [strip(e[0]), e[1]];
		return strip(e);
	}

	static function isError(e:Dynamic):Bool
		return Std.isOfType(e, Array) && (e : Array<Dynamic>).length == 2 && (e : Array<Dynamic>)[0] == "error";

	static function strip(e:Dynamic):Dynamic {
		if (!Std.isOfType(e, Array)) return e;
		var out:Array<Dynamic> = [];
		for (x in (e : Array<Dynamic>)) {
			if (isError(x) && ["invalid", "eof-in-string", "eof-in-url"].contains(x[1])) continue;
			out.push(strip(x));
		}
		return out;
	}

	static function same(a:Dynamic, b:Dynamic):Bool {
		if (a == null || b == null) return a == b;
		if (Std.isOfType(a, Array) && Std.isOfType(b, Array)) {
			var x:Array<Dynamic> = a, y:Array<Dynamic> = b;
			if (x.length != y.length) return false;
			for (k in 0...x.length)
				if (!same(x[k], y[k])) return false;
			return true;
		}
		if (Std.isOfType(a, Float) && Std.isOfType(b, Float)) {
			var x:Float = a, y:Float = b;
			return x == y || Math.abs(x - y) <= 1e-9 * Math.max(Math.abs(x), Math.abs(y));
		}
		return a == b;
	}

	// (our results in the fixtures' form)
	static function values(list:Array<CssValue>):Array<Dynamic>
		return [for (v in list) value(v)];

	static function value(v:CssValue):Dynamic
		return switch v {
			case Function(name, values, _, _): (["function", name] : Array<Dynamic>).concat(CssConformanceCheck.values(values));
			case Block(open, values, _):
				var b = switch open.kind {
					case OpenCurly: "{}";
					case OpenSquare: "[]";
					default: "()";
				}
				([b] : Array<Dynamic>).concat(CssConformanceCheck.values(values));
			case Token(t): switch t.kind {
					case Ident(v): ["ident", v];
					case Function(v): ["function-token", v];
					case AtKeyword(v): ["at-keyword", v];
					case Hash(v, id): ["hash", v, id ? "id" : "unrestricted"];
					case Str(v): ["string", v];
					case BadString: ["error", "bad-string"];
					case Url(v): ["url", v];
					case BadUrl: ["error", "bad-url"];
					case Delim(v): v;
					case Number(v, integer, text): ["number", text, v, integer ? "integer" : "number"];
					case Percentage(v, integer, text): ["percentage", text, v, integer ? "integer" : "number"];
					case Dimension(v, integer, text, unit): ["dimension", text, v, integer ? "integer" : "number", unit];
					case UnicodeRange(start, end): ["unicode-range", start, end];
					case Whitespace: " ";
					case Cdo: "<!--";
					case Cdc: "-->";
					case Colon: ":";
					case Semicolon: ";";
					case Comma: ",";
					case CloseSquare: ["error", "]"];
					case CloseParen: ["error", ")"];
					case CloseCurly: ["error", "}"];
					case OpenSquare | OpenParen | OpenCurly: ["open-token"];
				}
		}

	static function declaration(d:CssDeclaration):Dynamic
		return ["declaration", d.name, values(d.value), d.important];

	// (a block's contents in order: runs of declarations flattened among the rules)
	static function items(list:Array<CssRule>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		for (r in list)
			switch r {
				case Declarations(ds):
					for (d in ds)
						out.push(declaration(d));
				default:
					out.push(rule(r));
			}
		return out;
	}

	static function rule(r:CssRule):Dynamic
		return switch r {
			case At(name, prelude, block): ["at-rule", name, values(prelude), block == null ? null : items(block)];
			case Qualified(prelude, declarations, rules): ["qualified rule", values(prelude), [for (d in declarations) declaration(d)].concat(items(rules))];
			case Declarations(ds): ["declarations", [for (d in ds) declaration(d)]];
		}
}
