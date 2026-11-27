package helder.ui.fast;

import helder.ui.box.Box;
import helder.ui.box.BoxStyle;

// A node of text: a block of one paragraph, its lines broken to its width.
//
//   final title = new TextNode("Inbox", Style.of({fontSize: 20, fontWeight: 600}));
//   title.text = "Inbox (3)";
class TextNode extends Node {
	public var text(default, set):String;
	final run:Box;

	public function new(text:String, ?style:Style) {
		super(style);
		run = new Box(Text, box.style, this);
		run.flags |= Box.MADE;
		run.text = text;
		box.append(run);
		this.text = text;
	}

	function set_text(t:String):String {
		if (t == text) return t;
		text = t;
		run.text = t;
		changed(Resolve.LAYOUT, run);
		return t;
	}

	override function textual():Bool
		return true;

	// (null: in super(), its first style its box's)
	override function swapped(now:BoxStyle)
		if (run != null) run.restyle(now);
}
