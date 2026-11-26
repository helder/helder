import sys.io.File;

// Each file named parsed as a document, its tree beside it in html5lib's
// format (<file>.helder): the parse5 check's other half.
//
//   bin/dom/DomDump <file.html> ...
class DomDump {
	static function main()
		for (f in Sys.args())
			File.saveContent(f + ".helder", Dump.tree(helder.dom.Dom.parse(File.getContent(f))) + "\n");
}
