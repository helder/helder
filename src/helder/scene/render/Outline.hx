package helder.scene.render;

import helder.gfx.*;
import helder.math.Vec4;
import helder.scene.Node;

// Outlines around selected nodes, a PostProcess's (post.outline): the
// selection is data, a group (1 to 255) on a node (Outline.select: a
// component, its descendants drawn in it too), written by the view
// buffers' prepass (ViewBuffers: their normals' w) and its edges found in
// the composite, over everything drawn (see-through surfaces too). Each
// group has its colour (its alpha the outline's) and width in pixels:
//
//   post.outline = new Outline({width: 2, color: new Vec4(1, 0.8, 0.2, 1)});   // group 1
//   post.outline.group(2, new Vec4(0.3, 0.7, 1, 1), 3);
//   Outline.select(node);          // group 1; Outline.select(other, 2); Outline.select(node, 0): none
//
// The view buffers are drawn whole for it (scale 1). Nothing is allocated
// per frame; the groups' texture (256 x 2 RGBA8) is written when a group
// changes. Its groups alone: its part of the composite is OutlinePass's,
// linked by a program that sets it on a chain (post.outline's setter);
// selecting (Outline.select, Selection) links neither.
class Outline {
	// group 1's width in pixels and colour
	public var width(get, set):Float;
	public var color(get, set):Vec4;

	final widths:Array<Float> = [for (_ in 0...256) 0.0];
	final colors:Array<Vec4> = [for (_ in 0...256) new Vec4(0, 0, 0, 0)];
	// (a group changed since the groups' texture was written: OutlinePass's)
	@:allow(helder.scene.render) var changed = true;

	public function new(?options:{?width:Float, ?color:Vec4}) {
		group(1, options?.color ?? new Vec4(1, 0.8, 0.2, 1), options?.width ?? 2);
	}

	// a group's colour (its alpha the outline's) and width in pixels (at most 32)
	public function group(k:Int, color:Vec4, width:Float):Outline {
		if (k < 1 || k > 255) throw 'helder.scene: Outline: group $k is not 1 to 255';
		colors[k] = color;
		widths[k] = Math.max(0, Math.min(32, width));
		changed = true;
		return this;
	}

	function get_width():Float
		return widths[1];

	function set_width(v:Float):Float {
		group(1, colors[1], v);
		return v;
	}

	function get_color():Vec4
		return colors[1];

	function set_color(v:Vec4):Vec4 {
		group(1, v, widths[1]);
		return v;
	}

	// node and its descendants outlined in group (1 to 255; 0: not selected)
	public static function select(node:Node, group = 1) {
		var store = node.world.store(Selection.GROUP);
		if (group <= 0) store.remove(node) else store.set(node, Std.int(Math.min(255, group)));
	}

	// node's own group (0: none)
	public static function selected(node:Node):Int
		return node.world.store(Selection.GROUP).get(node) ?? 0;

	// (the widest group's width: the composite's taps)
	@:allow(helder.scene.render) function widest():Float {
		var w = 0.0;
		for (k in 1...256)
			if (colors[k].w > 0 && widths[k] > w) w = widths[k];
		return w;
	}

}
