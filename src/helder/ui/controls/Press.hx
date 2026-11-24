package helder.ui.controls;

import helder.ui.Event;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.access.Role;
import helder.ui.access.Semantics;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The behaviour of what is pressed (WAI-ARIA's button): a click, Enter or
// Space activates it (Ui's onActivate), none while it is disabled (then
// not focusable either). Its states are signals (hovered: never by touch;
// pressed: the pointer down on it and still over it, cancelled when it
// leaves; focusVisible: focused from the keyboard) and eased amounts
// (Eased). No look: root and part bind it to nodes, by ref, setting their
// slots (the control's, "button"; its part's, "button-icon"), the root's
// role, label, variant and size and its data-disabled (and a toggle's
// data-selected), which a look's recipes read.
//
//   final p = Press.of(props, "button");
//   <view:button ref={p.root}><image ref={p.part("icon")} .../></view:button>
class Press {
	public final hovered:Signal<Bool>;
	public final pressed:Signal<Bool>;
	public final focusVisible:Signal<Bool>;
	public final disabled:Read<Bool>;
	public final eased:Eased;
	public final slot:String;
	// the look it was made under (Themed's, else Look.base): its states' times, its parts' draws
	public final look:Look<Dynamic>;
	public var node(default, null):Null<Node> = null;
	// set before root binds: the root's name for assistive technology, variant, size
	public var label:Null<String> = null;
	public var variant:Null<String> = null;
	public var size:Null<String> = null;

	final onPress:Null<Void->Void>;
	var selected:Null<Read<Bool>>;
	var role:Role = Button;

	public function new(slot:String, ?disabled:Read<Bool>, ?onPress:Void->Void) {
		this.slot = slot;
		this.disabled = disabled ?? (false : Read<Bool>);
		this.onPress = onPress;
		look = Look.current();
		hovered = signal(false);
		pressed = signal(false);
		focusVisible = signal(false);
		eased = new Eased(look.times());
	}

	// a press of props' (a replaced rendering's: Look's render) for a control named slot
	public static function of(props:{?label:String, ?disabled:Read<Bool>, ?selected:Read<Bool>, ?onPress:Void->Void}, slot:String):Press {
		var p = new Press(slot, props.disabled, props.onPress);
		p.label = props.label;
		p.selected = props.selected;
		return p;
	}

	// activates it, as a press does (nothing while it is disabled)
	public function press()
		if (!disabled.peek()) activate(null);

	// binds the control's root node
	public function root(n:Node) {
		node = n;
		eased.node = n;
		n.slot = slot;
		var d = look.drawOf(slot);
		if (d != null) n.insert(d(eased, look), 0);
		if (variant != null) n.variant = variant;
		if (size != null) n.size = size;
		if (n.semantics == null) n.semantics = ({} : Semantics);
		var sem = n.semantics;
		sem.role = role;
		if (label != null) sem.label = label;
		n.onActivate = e -> if (!disabled.peek()) activate(e);
		var before = n.onStates;
		n.onStates = () -> {
			if (before != null) before();
			sync(false);
		};
		renderEffect(() -> disabled(), d -> {
			n.focusable = !d;
			sem.disabled = d;
			n.setAttr("data-disabled", d ? "" : null);
		});
		if (selected != null) renderEffect(() -> selected(), on -> {
			sem.checked = on;
			n.setAttr("data-selected", on ? "" : null);
		});
		bound(n);
		sync(true);
	}

	// binds a part: its slot, the control's followed by the part's name (a
	// look's draw for it: its shader's node under its children)
	public function part(name:String):Node->Void {
		var s = slot + "-" + name;
		return n -> {
			n.slot = s;
			var d = look.drawOf(s);
			if (d != null) n.insert(d(eased, look), 0);
		}
	}

	// (what the root binds beyond a press: a toggle's state)
	function bound(n:Node) {}

	// (a press: its handler)
	function activate(e:Null<Event>)
		if (onPress != null) onPress();

	function sync(first:Bool) {
		var n = node;
		if (n == null) return;
		var visible = n.focused && n.ui != null && n.ui.focusVisible;
		var down = n.pressed && n.hovered;
		if (hovered.peek() != n.hovered) hovered(n.hovered);
		if (pressed.peek() != down) pressed(down);
		if (focusVisible.peek() != visible) focusVisible(visible);
		eased.set(Eased.HOVER, n.hovered, first);
		eased.set(Eased.PRESSED, down, first);
		eased.set(Eased.FOCUS, visible, first);
	}

	// (a key a press ignores: Enter, where the pattern takes Space only)
	static inline function enter(e:Null<Event>):Bool
		return e != null && e.type == KeyDown && e.key == Key.ENTER;
}
