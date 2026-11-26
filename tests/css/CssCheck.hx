import haxe.DynamicAccess;
import helder.css.CssData;
import helder.css.CssGrammars;
import sys.io.File;

// The CSS fixtures against the property table, natively (bun run test css).
//
// values.json's properties are the table's (or custom ones), its rows the
// shapes its header names, their files listed; selectors.json's and
// reftests.json's entries complete; every property's and type's grammar
// parses. (The matcher's conformance over values.json comes with it.)
class CssCheck {
	static final failures = [];

	static function main() {
		var here = "tests/css/fixtures";
		var values:Dynamic = haxe.Json.parse(File.getContent('$here/values.json'));
		var files:Array<String> = values.files;
		var props:DynamicAccess<DynamicAccess<Array<Array<Dynamic>>>> = values.properties;
		var rows = 0;
		for (name => kinds in props) {
			need(name == "--*" || CssGrammars.property(name) != null, 'values.json: $name is not in the table');
			var custom = name == "--*" ? 1 : 0;
			for (kind => list in kinds) {
				var size = switch kind {
					case "valid" | "computed": 3 + custom;
					case "invalid": 2 + custom;
					case "shorthand": 3;
					case "inherits": 4;
					case _: -1;
				}
				need(size > 0, 'values.json: $name: $kind');
				for (r in list) {
					rows++;
					var file:Dynamic = r[size - 1];
					need(r.length == size || r.length == size + 1 && (kind == "valid" || kind == "computed"), 'values.json: $name $kind ${haxe.Json.stringify(r)}');
					need(Std.isOfType(file, Int) && file >= 0 && file < files.length, 'values.json: $name $kind: file ${haxe.Json.stringify(r)}');
				}
			}
		}
		var selectors:Dynamic = haxe.Json.parse(File.getContent('$here/selectors.json'));
		var valid:Array<Dynamic> = selectors.valid, scoped:Array<Dynamic> = selectors.scoped, invalid:Array<Dynamic> = selectors.invalid;
		for (s in valid.concat(scoped)) need(Std.isOfType(s.selector, String) && Std.isOfType(s.expect, Array) && Std.isOfType(s.level, Int), 'selectors.json: ${s.name}');
		for (s in invalid) need(Std.isOfType(s.selector, String), 'selectors.json: ${s.name}');
		var reftests:Dynamic = haxe.Json.parse(File.getContent('$here/reftests.json'));
		var dirs:DynamicAccess<Dynamic> = reftests.directories;
		var tests = 0, out = 0;
		for (dir => d in dirs) {
			var inScope:Array<Dynamic> = d.tests ?? [], outOf:Array<Dynamic> = d.out ?? [];
			for (t in inScope) {
				tests++;
				var refs:Array<Dynamic> = t.refs ?? [];
				need(Std.isOfType(t.name, String) && (t.type == "crash" ? refs.length == 0 : refs.length > 0), 'reftests.json: $dir/${t.name}');
			}
			for (o in outOf) {
				out++;
				need(o.length == 3 && Std.isOfType(o[2], String) && o[2] != "", 'reftests.json: $dir/${o[0]} out without a reason');
			}
		}
		var grammars = 0;
		for (p in CssData.properties) {
			grammars++;
			parses(p.name, p.syntax);
		}
		for (t in CssData.types) if (t.syntax != null) {
			grammars++;
			parses('<${t.name}>', t.syntax);
		}
		Sys.println('css: ${CssData.properties.length} properties, ${CssData.types.length} types, $grammars grammars; values.json $rows rows for ${props.keys().length} properties; '
			+ 'selectors.json ${valid.length + scoped.length + invalid.length}; reftests.json $tests in scope, $out out');
		if (failures.length > 0) {
			for (f in failures) Sys.println('  $f');
			Sys.exit(1);
		}
	}

	static function parses(name:String, syntax:String)
		try CssGrammars.parse(syntax) catch (e) failures.push('$name: ${e.message}');

	static function need(ok:Bool, what:String)
		if (!ok) failures.push(what);
}
