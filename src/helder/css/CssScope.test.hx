package helder.css;

import helder.css.CssScope;
import helder.test.Test;

// CSS modules compiled: names scoped to their file, :global and :local,
// composes from the same file, another and global, the export, and the
// errors at their line and column (a missing name or file, a cycle).
private final DIR = "src/helder/css/test-modules";

function tests() {
	describe("CssScope", () -> {
		test("names scoped to their file, :global left as written, :local scoped again", () -> {
			var m = CssScope.compile('$DIR/card.module.css');
			var h = haxe.crypto.Md5.encode('$DIR/card.module.css').substr(0, 6);
			equals(m.key, 'card_$h');
			equals([for (n in m.names) n.name], ["card", "card-title", "bold", "main", "inner", "button", "wide"]);
			equals(m.diagnostics.length, 0);
			var printed = [for (r in m.rules) switch r {
				case Qualified(p, _, _): StringTools.trim(Css.serialize(p));
				case At(n, _, b): '@$n ' + [for (x in b ?? []) switch x {
					case Qualified(p, _, _): StringTools.trim(Css.serialize(p));
					case _: "";
				}].join("");
				case _: "";
			}];
			equals(printed, [
				'.card_card_$h', '.card_card-title_$h', '.card_bold_$h', '#card_main_$h .card_card_$h:hover, .dark .card_card_$h', '.page .card_inner_$h',
				'.card_button_$h', '@media .card_wide_$h'
			]);
		});
		test("composes: the same file, another, global; taken out of the rules", () -> {
			var m = CssScope.compile('$DIR/card.module.css');
			var h = haxe.crypto.Md5.encode('$DIR/card.module.css').substr(0, 6), b = haxe.crypto.Md5.encode('$DIR/base.module.css').substr(0, 6);
			var names = [for (n in m.names) n.name => n.value];
			equals(names["card-title"], 'card_card-title_$h card_bold_$h');
			equals(names["button"], 'card_button_$h base_base_$b base_reset_$b shadow');
			equals([for (c in m.composes) haxe.io.Path.withoutDirectory(c.file)], ["base.module.css"]);
			equals(m.files.map(f -> haxe.io.Path.withoutDirectory(f)), ["card.module.css", "base.module.css"]);
			var sheet = CssScope.sheet(m);
			var declared = [for (r in sheet.rules) switch r {
				case Style(_, ds): [for (d in ds) d.property].join(",");
				case _: "";
			}];
			equals(declared[1], "font-size");
		});
		test("a cycle across files, at the composes that closes it", () -> {
			var m = CssScope.compile('$DIR/cycle-a.module.css');
			equals([for (d in m.diagnostics) '${haxe.io.Path.withoutDirectory(d.file)}:${d.line}:${d.column}: ${d.message}'],
				["cycle-b.module.css:1:6: composes: a cycle: cycle-a.module.css → cycle-b.module.css → cycle-a.module.css"]);
		});
		test("errors at their line and column", () -> {
			var m = CssScope.compile('$DIR/broken.module.css');
			equals([for (d in m.diagnostics) '${d.line}:${d.column}: ${d.message}'], [
				"2:7: composes: only in a rule of one class (.name { composes: ... })",
				"7:1: :global takes a selector: :global(.name)",
				"1:16: composes: no class .missing in this file",
				"3:6: composes: no file none.module.css",
				"4:16: composes: no class .gone in ./base.module.css",
				"6:16: composes: a cycle: .v → .u → .v"
			]);
		});
		test("TypeScript's module and declaration, exactly typed", () -> {
			var t = CssScope.typescript('$DIR/base.module.css');
			var b = haxe.crypto.Md5.encode('$DIR/base.module.css').substr(0, 6);
			equals(t.declaration.split("\n").slice(1).join("\n"), "declare const names: {readonly base: string; readonly reset: string};\nexport default names;\n");
			equals(t.source.split("\n")[1], 'const names: {readonly base: string; readonly reset: string} = Object.freeze({base: "base_base_$b base_reset_$b", reset: "base_reset_$b"});');
			equals(t.haxeType, 'helder.css.modules.Css_base_$b');
			equals(CssScope.typescript('$DIR/card.module.css').declaration.indexOf('readonly "card-title": string') > 0, true);
		});
	});
}
