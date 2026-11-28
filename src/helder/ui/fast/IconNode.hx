package helder.ui.fast;

import helder.ui.box.Box;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxStyle;

// An icon: lucide's of that name (helder.ui.controls.Icons), drawn in its
// text colour at its size.
//
//   new IconNode("check", Style.of({width: 12, height: 12}));
class IconNode extends Node {
	public var name(default, set):Null<String>;

	public function new(?name:String, ?style:Style) {
		super(style);
		this.name = name;
	}

	function set_name(v:Null<String>):Null<String> {
		if (v == name) return v;
		name = v;
		box.svg = v == null ? null : helder.ui.controls.Icons.svg(v);
		changed(Resolve.LAYOUT);
		return v;
	}

	override function blank():Node
		return new IconNode();

	override function copied(c:Node)
		(cast c : IconNode).name = name;

	override function kindOf(s:BoxStyle):BoxKind
		return BlockReplaced;

	// (an inline SVG's paint: its text colour, currentColor)
	override function dressed(b:Box)
		b.flags |= Box.INLINE_SVG;
}
