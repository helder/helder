package helder.dom;

// HTML in, a DOM out, and back: the WHATWG HTML parser (scripting off) and
// the HTML fragment serialization algorithm.
//
//   var doc = Dom.parse("<!doctype html><title>A</title><p class=x>Hi");
//   doc.body.firstElementChild.className;   // "x"
//   Dom.serialize(doc);                     // the document as markup
class Dom {
	// a document from markup (never throws; errors, when given, collects the parse errors)
	public static function parse(html:String, ?errors:Array<ParseError>):Document
		return TreeBuilder.document(html, errors);

	// markup parsed as context's children would be (innerHTML's parse), in a fragment of context's document
	public static function parseFragment(html:String, context:Element, ?errors:Array<ParseError>):DocumentFragment
		return TreeBuilder.fragment(html, context, errors);

	// an XML document from its text (XML 1.0 and its namespaces; never throws:
	// the first well-formedness error ends the tree there, and is in errors when given)
	public static function parseXml(xml:String, ?errors:Array<ParseError>):Document
		return XmlParser.document(xml, errors);

	// a node as markup: an element with its tags, a document or fragment its children
	public static function serialize(node:Node):String
		return Serializer.node(node);
}
