package helder.ui.controls;

import helder.ui.Event;
import helder.ui.Node;
import helder.ui.access.Role;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The behaviour of what is on or off (WAI-ARIA's checkbox and switch): a
// Press whose activation toggles it, Space and a click (a switch's Enter
// too; a checkbox's not, as the pattern has it), mixed (a checkbox's
// indeterminate) turning on. Its root is a checkbox or a switch to
// assistive technology, checked or mixed, and data-state checked,
// unchecked or mixed for a look's recipes. checked given with no onChange:
// toggled by nothing but the caller; neither: its own state.
//
//   final sw = Toggle.of(props, "switch");
//   <view ref={sw.root}><view ref={sw.part("knob")}/></view>
class Toggle extends Press {
	public final checked:Read<Bool>;
	public final mixed:Read<Bool>;
	final onChange:Null<Bool->Void>;
	final own:Null<Signal<Bool>>;

	public function new(control:String, role:Role, ?checked:Read<Bool>, ?mixed:Read<Bool>, ?onChange:Bool->Void, ?disabled:Read<Bool>) {
		super(control, disabled, null);
		this.role = role;
		own = checked == null ? signal(false) : null;
		this.checked = checked ?? (own : Read<Bool>);
		this.mixed = mixed ?? (false : Read<Bool>);
		this.onChange = onChange;
	}

	// a toggle of props' (a replaced rendering's: Look's render) for a
	// control: a switch ("switch") or a checkbox (any other)
	public static function of(props:{label:String, ?checked:Read<Bool>, ?indeterminate:Read<Bool>, ?onChange:Bool->Void, ?disabled:Read<Bool>},
			control:String):Toggle {
		var t = new Toggle(control, control == "switch" ? Switch : CheckBox, props.checked, props.indeterminate, props.onChange, props.disabled);
		t.label = props.label;
		return t;
	}

	// turns it over (mixed: on), as a press does
	public function toggle() {
		if (disabled.peek()) return;
		var next = mixed.peek() || !checked.peek();
		if (own != null) own(next);
		if (onChange != null) onChange(next);
	}

	override function activate(e:Null<Event>)
		if (!(role == CheckBox && Press.enter(e))) toggle();

	override function bound(n:Node) {
		var first = true;
		renderEffect(() -> mixed() ? 2 : checked() ? 1 : 0, s -> {
			n.semantics.checked = s == 1;
			n.semantics.mixed = s == 2;
			n.setAttr("data-state", s == 2 ? "mixed" : s == 1 ? "checked" : "unchecked");
			eased.set(Eased.CHECKED, s != 0, first);
			first = false;
		});
	}
}
