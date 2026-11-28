package helder.ui.fast;

import helder.ui.box.Box;
import helder.ui.box.BoxStyle;

// A node of text: a block of one paragraph, its lines broken to its width.
//
//   final title = new TextNode("Inbox", Style.of({fontSize: 20, fontWeight: 600}));
//   title.text = "Inbox (3)";
class TextNode extends Node {
	public var text(default, set):String;
	@:allow(helder.ui.fast) final run:Box;

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

	// Its text and its spans', in order.
	public function allText():String {
		if (kids.length == 0) return text;
		var out = new StringBuf();
		out.add(text);
		for (c in kids) if (Std.isOfType(c, TextNode) && !c.box.style.none) out.add((cast c : TextNode).allText());
		return out.toString();
	}

	override function blank():Node
		return new TextNode("");

	override function copied(c:Node)
		(cast c : TextNode).text = text;

	// (null: in super(), its first style its box's)
	override function swapped(now:BoxStyle)
		if (run != null) run.restyle(now);
}
