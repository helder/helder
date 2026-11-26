import helder.css.CssCascade;
import helder.css.CssModule;
import helder.dom.Dom;

// The CSS modules probe (the css lane): a document styled through a module
// alone (CssModule.load: scoped, composed, compiled when the program is).
// Built with -dce full and symbols, its symbols hold no CSS tokenizer or
// parser (as ThemeProbe's). Prints what it computed. With --typescript
// <dir>, writes the modules' TypeScript declarations there (CssScope's
// entry point), for tsc to check a program against.
class ModuleProbe {
	static function main() {
		var args = Sys.args();
		#if css.typescript
		if (args[0] == "--typescript") {
			for (m in ["card", "base"]) {
				var t = helder.css.CssScope.typescript('tests/css/modules/$m.module.css');
				sys.io.File.saveContent('${args[1]}/$m.module.d.css.ts', t.declaration);
			}
			return;
		}
		#end
		final card = CssModule.load("modules/card.module.css");
		var doc = Dom.parse('<!doctype html><div class="${card.list}"><p class="${card.card}">a</p><p class="${card.card} ${card.cardTitle}">b</p></div>');
		var styles = CssCascade.themed(doc, []);
		var ps = doc.getElementsByTagName("p");
		var a = styles.computed(ps.item(0)), b = styles.computed(ps.item(1));
		Sys.println([a.text("padding-top"), a.text("color"), a.text("margin-top"), b.text("margin-top"), b.text("font-size"), b.text("font-weight")].join(" "));
	}
}
