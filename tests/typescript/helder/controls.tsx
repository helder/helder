// helder.ui's controls from TypeScript, headless (UiProbe): Button,
// Checkbox and Switch in Look.base, pressed, toggled by a click and by
// Space, light and dark; a look of the program's (Look.base.with: a token,
// a variant of its own, a part, a rendering replaced), its own variant
// checked by the types (the @ts-expect-error below: the base look has no
// "soft"), styles written as markup writes them ('0 20').
import { signal, Render } from "helder/view";
import { Button, Checkbox, Switch, PathBar, Themed, Look, tone, Toggle, Key, Node, type CheckboxProps, type PathSegment } from "helder/ui";
import { UiProbe } from "./ui-probe";

const saved = signal(0), terms = signal(false), dark = signal(true);
const root = UiProbe.root(320, 240);
Render.render(
	<view padding={8} row-gap={8}>
		<Button tag="save" variant="primary" onPress={() => saved(n => n + 1)}>Save</Button>
		<Button tag="cancel">Cancel</Button>
		<Checkbox tag="terms" label="Accept the terms" checked={terms} onChange={terms}/>
		<Switch tag="dark" label="Dark mode" checked={dark} onChange={dark}/>
	</view>,
	root
);
UiProbe.click("save");
console.log(saved(), "|", UiProbe.slot("save"), "|", UiProbe.slot("cancel"));
console.log(UiProbe.background("save"), UiProbe.background("cancel"));
UiProbe.dark(true);
console.log(UiProbe.background("save"), UiProbe.background("cancel"));
UiProbe.dark(false);
UiProbe.click("terms");
UiProbe.click("dark");
UiProbe.key(Key.SPACE);
console.log(terms(), dark());
console.log(UiProbe.dump());

// a rendering of the program's: a lamp for every checkbox, its behaviour and access kept
function Lamp(props: CheckboxProps<any>) {
	const t = Toggle.of(props, "checkbox");
	return <view tag="lamp" ref={(n: Node) => t.root(n)} direction="row" column-gap={4}>
		<view ref={t.part("bulb")} width={12} height={12}/>
		<text>{() => (t.checked() ? "on: " : "off: ") + props.label}</text>
	</view>;
}

const look = Look.base.with({
	tokens: { accent: tone("#e11d48") },
	button: t => ({ variants: { variant: { soft: { root: { background: t.accentSoft, color: t.accentInk, padding: "0 20" } } } } }),
	switch: () => ({ knob: { radius: 3 } }),
	render: { checkbox: Lamp }
});
const porch = signal(false);
Render.render(
	<Themed look={look}>
		<view padding={8} row-gap={8}>
			<look.Button tag="go" variant="primary">Go</look.Button>
			<look.Button tag="soft" variant="soft">Soft</look.Button>
			<Checkbox label="Porch" checked={porch} onChange={porch}/>
		</view>
	</Themed>,
	UiProbe.root(320, 200)
);
console.log(UiProbe.background("go"), UiProbe.background("soft"), UiProbe.slot("soft"), UiProbe.padding("soft"));
UiProbe.click("lamp");
console.log(porch());
console.log(UiProbe.dump());

function never() {
	// @ts-expect-error: Look.base's buttons have no variant "soft"
	return <Button variant="soft">Soft</Button>;
}
console.log(typeof never);

const path = signal<PathSegment[]>([{label: "Home"}, {label: "Pictures"}]);
const editing = signal(false);
let visited = -1, separator = "", submitted = "";
Render.render(
	<PathBar tag="location" segments={path} size="md" editing={editing} text="/Home/Pictures"
		onNavigate={i => { visited = i; }}
		onSeparator={(i, anchor) => { separator = i + " " + anchor.slot; }}
		onSubmit={text => { submitted = text; }}/>,
	UiProbe.root(320, 160)
);
UiProbe.click("pathbar-segment");
UiProbe.click("pathbar-separator");
console.log(visited, separator, UiProbe.slot("location"));
editing(true);
UiProbe.dump();
UiProbe.type("/New");
UiProbe.key(Key.ENTER);
console.log(submitted, editing());
