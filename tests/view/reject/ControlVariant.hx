// A control's variant is checked against its look's, at the attribute: the
// look's own (with's "soft") on look.Button, none on Look.base's Button.
// expect: ControlVariant.hx:12: characters
// expect: "soft" is no button variant of this look: danger, ghost, primary, secondary
import helder.ui.controls.Look;
import helder.ui.controls.Standard;

class ControlVariant implements helder.view.Markup {
	static function main() {
		var look = Look.base.with({button: t -> {variants: {variant: {soft: {root: {background: t.accentSoft}}}}}});
		var ok = <look.Button variant="soft">Soft</look.Button>;
		var e = <Standard.Button variant="soft">Soft</Standard.Button>;
	}
}
