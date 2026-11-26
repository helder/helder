package helder.dom;

// The DOM's CDATASection: XML's <![CDATA[...]]>, a Text node of its own type.
@:allow(helder.dom)
class CDATASection extends Text {
	function new(doc:Document, data:String)
		super(doc, data, Node.CDATA_SECTION_NODE);

	override function get_nodeName():String
		return "#cdata-section";

	override function cloneOne(document:Document):Node
		return new CDATASection(document, value);
}
