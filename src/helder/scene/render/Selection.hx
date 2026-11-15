package helder.scene.render;

import helder.scene.Node;
import helder.scene.StoreKind;

// The selection as data: a node's group (1 to 255; 0 none), a component
// (Outline.select writes it, <node outline>'s prop too), which the view
// buffers' prepass draws for post.outline. A module of its own: selecting
// links neither the view buffers nor the outline's passes.
class Selection {
	// a node's own group
	@:noCompletion public static final GROUP = new StoreKind<Int>("selection");

	// a node's group: its own, else the nearest of its ancestors' (0: none)
	public static function groupOf(node:Node):Int {
		var store = node.world.store(GROUP);
		if (store.length == 0) return 0;
		var n = node;
		while (!n.isNone) {
			var g = store.get(n);
			if (g != null) return g;
			n = n.parent;
		}
		return 0;
	}
}
