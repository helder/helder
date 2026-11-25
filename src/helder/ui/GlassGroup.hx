package helder.ui;

import helder.ui.Glass.GlassNative;

// Glass that merges, `<glass-group spacing={16}>` in markup (SwiftUI's
// GlassEffectContainer): the glass inside it drawn together, under all of
// their children, those nearer each other than spacing points blending
// into one shape. The system's container where its glass is the
// system's (NSGlassEffectContainerView, UIGlassContainerEffect), a view in
// the layer tree its glass views are in.
class GlassGroup extends Node {
	public var spacing(default, set) = 0.0;

	@:allow(helder.ui.Glass) var native:Null<GlassNative> = null;
	// (its drawing's, helder.ui.draw.GlassPass: a GPU's, natively)
	@:allow(helder.ui.GlassDraw) var pass:Any = null;

	public function new()
		super("glass-group");

	function set_spacing(v:Float):Float {
		spacing = v;
		paintChanged();
		return v;
	}

	// the glass it draws: its descendants', not those of a group inside it
	public function glass():Array<Glass> {
		var out = [];
		function walk(n:Node)
			for (c in n.children) {
				if (Std.isOfType(c, Glass)) out.push(cast c);
				if (!Std.isOfType(c, GlassGroup)) walk(c);
			}
		walk(this);
		return out;
	}

	@:noCompletion override public function hasContent():Bool
		return true;

	@:noCompletion override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (systemLayer != null) return;
		GlassDraw.group(canvas, this);
	}

	override function attach(u:Null<Ui>) {
		if (ui != null && ui != u) {
			@:privateAccess ui.natives.remove(this);
			drop();
		}
		super.attach(u);
		if (u != null && @:privateAccess u.natives.indexOf(this) < 0) @:privateAccess u.natives.unshift(this);
	}

	function drop() {
		systemLayer = null;
		for (g in glass())
			@:privateAccess g.drop();
		if (native != null) native.dispose();
		native = null;
	}

	// (before its glass, which goes in its container: Ui.natives has it first)
	override function syncNative() {
		if (ui == null) return;
		if (!@:privateAccess ui.layered) {
			if (native != null) {
				drop();
				paintChanged();
			}
			return;
		}
		if (native == null) {
			native = GlassNative.make(ui, null, true);
			if (native == null) return;
			paintChanged();
		}
		native.spacing(spacing);
		systemLayer = native.slot;
		systemLayer.shown = visible() && width > 0 && height > 0;
	}
}
