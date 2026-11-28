package helder.ui.view;

// Markup's style attributes (NodeRenderer): an attribute named as a Style
// field (CSS's name in camel: alignItems) sets that field over the node's
// style (Node.styleAttr), its value as markup gives it: a number, a Bool,
// the field's own type, or a string as CSS writes it ("8 12", "#3b82f6",
// "space-between", "50%"), Attrs' to convert.
class StyleAttrs {
	public static function set(n:helder.ui.Node, name:String, v:Dynamic)
		if (!n.styleAttr(name, v)) throw 'helder.ui: no style attribute $name';
}
