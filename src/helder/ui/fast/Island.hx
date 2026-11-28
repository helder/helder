package helder.ui.fast;

import helder.css.CssCascade;
import helder.css.CssSheet;
import helder.dom.Document;
import helder.ui.box.Box;
import helder.ui.box.BoxTree;

// A DOM document in a fast tree, its boxes in the tree's own: laid out,
// painted and hit with the fast nodes around it, its text selected across
// them (one tree, BoxTexts). Styled by HTML's cascade and its sheets, its
// root inheriting the island's text (font, size, line height, colour) as
// a shadow root inherits its host's; its media the screen, as wide as the
// tree. What links helder.dom and the cascade: an Island used.
//
//   list.append(new Island(Dom.parse("<p>Hello <b>world</b></p>")));
class Island extends Node {
	public final document:Document;
	final sheets:Array<CssSheet>;
	var built:Null<BoxTree> = null;
	// (the text it was styled under: another made again)
	var builtFor:Null<helder.ui.flow.InlineBasicStyle> = null;

	public function new(document:Document, ?sheets:Array<CssSheet>, ?style:helder.ui.fast.Style) {
		this.document = document;
		this.sheets = sheets ?? [];
		super(style ?? helder.ui.fast.Style.of({display: helder.ui.Display.Block}));
	}

	override function blank():Node
		return new Island(document, sheets);

	// (a label for each of its paragraphs, their boxes' text)
	@:allow(helder.ui.fast) override function accessOwn(tree:Tree, out:Array<helder.ui.access.AccessNode>):Null<Array<Int>>
		return tree.paragraphs(box, out);

	@:allow(helder.ui.fast) override function resolve(text:helder.ui.flow.InlineBasicStyle, theme:Theme, group:Int) {
		super.resolve(text, theme, group);
		if (built == null || builtFor != box.style.text) build();
	}

	// (its document's boxes made, under its own)
	function build() {
		var t = box.style.text;
		builtFor = t;
		var families = [for (f in t.families) '"$f"'].join(", ");
		var height = t.height == t.height ? '${t.height}px' : "normal";
		var root = ':root { font-family: $families; font-size: ${t.size}px; line-height: $height; color: #${StringTools.hex(t.colour & 0xFFFFFF, 6)} }';
		var t0 = hostTree(), width = t0 == null ? 800.0 : t0.width;
		var styles = CssCascade.styles(document, {
			user: [CssSheet.parse(root, User)],
			author: sheets,
			media: {type: "screen", width: width, height: 600, resolution: 1, color: 8}
		});
		built = BoxTree.build(document, styles, {contexts: helder.ui.flow.Contexts.all(), counters: s -> new helder.css.CssCounters(s)});
		while (box.first != null) box.first.remove();
		box.append(built.root);
		changed(Resolve.LAYOUT);
	}

	function hostTree():Null<Tree> {
		var n:Node = this;
		while (n.parent != null) n = n.parent;
		return n.tree;
	}
}
