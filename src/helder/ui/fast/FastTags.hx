package helder.ui.fast;

import helder.view.Render;
import helder.view.graph.Graph;

typedef FastView = helder.view.ViewOf<FastRenderer>;

// The boundary between helder.ui's markup and fast nodes' (import
// helder.ui.fast.FastTags.*): a Tree in helder.ui's tree, its content fast
// nodes, a root node filling it (style: the root's, a fast Style or
// StyleProps; theme: its theme, a Theme or what reads one).
//
//   <Surface title="Todo"><Fast theme={app}><view padding={24}>...</view></Fast></Surface>
class FastTags {
	public static function Fast(props:{
		?theme:Dynamic,
		?style:Dynamic,
		?flexGrow:Float,
		?ref:Tree->Void,
		?children:FastView
	}):helder.ui.Node {
		var root = new Node(Style.of({height: "100%"}));
		var tree = new Tree(root);
		tree.style.flexGrow = props.flexGrow ?? 1;
		if (props.style != null) FastRenderer.setStyle(root, props.style);
		var t:Dynamic = props.theme;
		if (t != null) Render.isReactive(t) ? Graph.renderEffect(() -> (Render.read(t) : Theme), (v:Theme) -> tree.palette = v) : tree.palette = Render.read(t);
		Render.insert(props.children, root, null);
		if (props.ref != null) props.ref(tree);
		return tree;
	}
}
