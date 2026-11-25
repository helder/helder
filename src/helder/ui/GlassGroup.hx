package helder.ui;

import helder.ui.Glass.GlassNative;

// Glass that merges, a view's glassSpacing in markup (`<view
// glassSpacing={16}>`, Node.glassSpacing; SwiftUI's GlassEffectContainer):
// the glass inside it drawn together, under all of their children, those
// nearer each other than spacing points blending into one shape. The
// system's container where its glass is the system's
// (NSGlassEffectContainerView, UIGlassContainerEffect), a view in the
// layer tree its glass views are in. Its node's, made by GlassGroup.of.
@:allow(helder.ui) @:access(helder.ui.Ui) @:access(helder.ui.Glass) @:access(helder.ui.Node) class GlassGroup implements GlassGrouping {
	// node's glass merged, nearer than spacing points (null: not a group; Node.glassSpacing)
	public static function of(node:Node, spacing:Null<Float>) {
		var g:Null<GlassGroup> = cast node.glassGroup;
		if (spacing == null) {
			if (g != null) g.dispose();
			node.glassGroup = null;
			node.paintChanged();
			return;
		}
		if (g == null) {
			node.glassGroup = g = new GlassGroup(node);
			g.attached(node.ui);
		}
		g.spacing = spacing;
	}

	public final node:Node;
	public var spacing(default, set) = 0.0;

	var native:Null<GlassNative> = null;
	// (its drawing's, helder.ui.draw.GlassPass: a GPU's, natively)
	var pass:Any = null;

	function new(node:Node)
		this.node = node;

	function set_spacing(v:Float):Float {
		spacing = v;
		@:privateAccess node.paintChanged();
		return v;
	}

	// the glass it draws: its descendants', not those of a group inside it
	public function glass():Array<Glass> {
		var out = [];
		function walk(n:Node)
			for (c in n.children) {
				if (Std.isOfType(c, Glass)) out.push(cast c);
				if (c.glassGroup == null) walk(c);
			}
		walk(node);
		return out;
	}

	// (its node's paintContent, attach and syncNative)
	public function paint(canvas:Canvas) {
		if (node.systemLayer != null) return;
		GlassDraw.group(canvas, this);
	}

	public function attach(u:Null<Ui>) {
		var ui = node.ui;
		if (ui != null && ui != u) {
			ui.natives.remove(node);
			drop();
		}
	}

	public function attached(u:Null<Ui>)
		if (u != null && u.natives.indexOf(node) < 0) u.natives.unshift(node);

	function drop() {
		node.systemLayer = null;
		for (g in glass())
			g.drop();
		if (native != null) native.dispose();
		native = null;
	}

	// (before its glass, which goes in its container: Ui.natives has it first)
	public function sync() {
		var ui = node.ui;
		if (ui == null) return;
		if (!ui.layered) {
			if (native != null) {
				drop();
				node.paintChanged();
			}
			return;
		}
		if (native == null) {
			native = GlassNative.make(ui, null, true);
			if (native == null) return;
			node.paintChanged();
		}
		native.spacing(spacing);
		node.systemLayer = native.slot;
		node.systemLayer.shown = node.visible() && node.width > 0 && node.height > 0;
	}

	// (its node no longer a group)
	public function dispose() {
		var ui = node.ui;
		if (ui != null) ui.natives.remove(node);
		drop();
	}
}
