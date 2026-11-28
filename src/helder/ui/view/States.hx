package helder.ui.view;

import helder.ui.*;
import helder.ui.Style.StyleProps;
import helder.view.graph.Signal;
import helder.view.graph.Graph.*;

// A node's states as signals (React Aria's render props): hovered,
// pressed, focused, focusVisible (focused with the ring shown), disabled
// (the attribute disabled or data-disabled), and any attribute's value
// (attr("data-state"): "checked", "open"...), each following the node
// (Node.onStates). A widget's style prop is a function of them:
//   <Button label="Save" style={s -> s.pressed() ? {opacity: 0.8} : {}}/>
class States {
	public final hovered:Signal<Bool>;
	public final pressed:Signal<Bool>;
	public final focused:Signal<Bool>;
	public final focusVisible:Signal<Bool>;
	public final disabled:Signal<Bool>;
	final node:Node;
	final attrs = new Map<String, Signal<Null<String>>>();

	function new(n:Node) {
		node = n;
		hovered = signalOf(n.hovered, {ownedWrite: true});
		pressed = signalOf(n.pressed, {ownedWrite: true});
		focused = signalOf(n.focused, {ownedWrite: true});
		focusVisible = signalOf(visible(), {ownedWrite: true});
		disabled = signalOf(isDisabled(), {ownedWrite: true});
		var before = n.onStates;
		n.onStates = () -> {
			if (before != null) before();
			hovered(n.hovered);
			pressed(n.pressed);
			focused(n.focused);
			focusVisible(visible());
			disabled(isDisabled());
			for (k => s in attrs)
				s(n.attr(k));
		};
	}

	inline function visible():Bool
		return node.focused && node.ui != null && node.ui.focusVisible;

	inline function isDisabled():Bool
		return node.attr("disabled") != null || node.attr("data-disabled") != null;

	// an attribute's value as a signal (null: not set; "": present without a value)
	public function attr(name:String):Signal<Null<String>> {
		var s = attrs.get(name);
		if (s == null) attrs.set(name, s = signalOf(node.attr(name), {ownedWrite: true}));
		return s;
	}

	// the states of a node (made once for it)
	public static function of(n:Node):States {
		var s:Null<States> = @:privateAccess n.statesOf;
		if (s == null) @:privateAccess n.statesOf = s = new States(n);
		return s;
	}

	// applies style(states) to n now and whenever what it reads changes:
	// over the style it had when this was applied (what it no longer gives
	// that style's again)
	public static function apply(n:Node, style:Null<States->StyleProps>) {
		if (style == null) return;
		var s = of(n), base = n.style;
		renderEffect(() -> style(s), (p:Null<StyleProps>) -> n.style = p == null ? base : base.with(p));
	}
}
