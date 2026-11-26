import sys.io.File;

// Each file named parsed as a document, its tree beside it in html5lib's
// format (<file>.helder): the parse5 check's other half. A document that
// fails is named on stderr with its error, the others still dumped; then
// the exit code is 1.
//
//   bin/dom/DomDump <file.html> ...
class DomDump {
	static function main() {
		var failed = 0;
		for (f in Sys.args())
			try {
				File.saveContent(f + ".helder", Dump.tree(helder.dom.Dom.parse(File.getContent(f))) + "\n");
			} catch (e:haxe.Exception) {
				failed++;
				Sys.stderr().writeString('DomDump: $f: ${e.message}\n${e.stack}\n');
			}
		if (failed > 0) Sys.exit(1);
	}
}
