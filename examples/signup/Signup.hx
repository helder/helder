// title: Sign-up card
// summary: helder's controls in a card: a field, a checkbox, a switch, a badge and buttons, in a look of its own, light and dark
// tags: ui, styles, controls
// demo: canvas 420x360
import helder.ui.*;
import helder.ui.controls.Look;
import helder.ui.controls.Standard;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// A card of helder's controls (helder.ui.controls: a Checkbox, a Switch,
// Buttons; their keys, states and accessibility theirs), in Look.base with
// the card's own parts (a slot each: card, muted, badge, input), its colours
// the look's tokens, inline too (Look.ref). The switch turns dark mode on
// (the window's Ui.dark); Sign up waits for the terms.
class Signup implements Markup {
	static function main() {
		var dark = signal(false);
		UiWindow.run(<Surface title="Sign up" width={420} height={360} dark={dark}>
			<Standard.Themed look={look}>{view(dark)}</Standard.Themed>
		</Surface>);
	}

	// (the card in its look, light or dark, as the window shows it: Signup.story.hx's screens)
	public static function themed(dark:Bool):View {
		var d = signal(dark), root:Null<Node> = null;
		effect(() -> d(), x -> if (root?.ui != null) root.ui.dark = x);
		return <Standard.Themed look={look}>
			<view flexGrow={1} ref={(__part:helder.ui.Part) -> {var n:Node = cast __part; {
				root = n;
				if (n.ui != null) n.ui.dark = d.peek();
			};}}>{view(d)}</view>
		</Standard.Themed>;
	}

	// helder's look, and the card's parts in its tokens (made at its first
	// read: a static's initializer may run before those of the libraries it
	// calls, whose tables are null then)
	public static var look(get, never):Look<Dynamic>;

	static var made:Null<Look<Dynamic>> = null;

	static function get_look():Look<Dynamic>
		return made ??= Look.base.with({
		parts: {
			card: t -> {rowGap: 24, padding: 24, borderRadius: t.radiusSurface, borderWidth: 1, borderColor: t.line, background: t.surface},
			muted: t -> {color: t.fg2},
			badge: t -> {padding: [2, 8], borderRadius: t.radius - 2, background: t.well, color: t.fg2, fontSize: t.small, fontWeight: t.medium},
			input: t -> {height: t.control, padding: [0, 12], borderRadius: t.radius, borderWidth: 1, borderColor: t.edge, background: t.surface,
				hover: {borderColor: t.edgeStrong}}
		}
	});

	public static function view(dark:Signal<Bool>):View {
		var email = signal(""), terms = signal(false), sent = signal(false);
		return <view flexGrow={1} padding={24} background={Look.ref.canvas} color={Look.ref.fg} fontFamily="Inter" fontSize={14}>
			<view slot="card">
				<view flexDirection="row" alignItems="start">
					<view flexGrow={1} rowGap={4}>
						<text fontSize={16} fontWeight={600}>Create an account</text>
						<text slot="muted">{() -> sent() ? "Check your inbox" : "Enter your email below"}</text>
					</view>
					<text slot="badge">Beta</text>
				</view>
				<view rowGap={12}>
					<field slot="input" value={email} placeholder="m@example.com" aria-label="Email" onInput={e -> email(e.text)}/>
					<Standard.Checkbox label="Accept terms" checked={terms} onChange={v -> terms(v)}/>
					<Standard.Switch label="Dark mode" checked={dark} onChange={v -> dark(v)}/>
				</view>
				<view flexDirection="row" columnGap={8}>
					<Standard.Button onPress={() -> sent(false)}>Cancel</Standard.Button>
					<Standard.Button variant="primary" disabled={() -> !terms()} onPress={() -> sent(true)}>Sign up</Standard.Button>
				</view>
			</view>
		</view>;
	}
}
