package helder.dom;

// A document's mode, from its doctype (the HTML parser's): CSS layout's
// quirks follow it.
enum abstract DocumentMode(String) to String {
	var NoQuirks = "no-quirks";
	var Quirks = "quirks";
	var LimitedQuirks = "limited-quirks";
}
