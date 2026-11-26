// title: Navigation
// summary: Screens by path on a stack: a list, a detail screen, settings; the system's back, transitions, URLs
// tags: ui, navigation
// demo: canvas 390x640
import helder.ui.nav.Routes;
import helder.ui.Stack;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

// A list, a detail screen and a settings screen on a Routes's stack: a
// press pushes, the header's back (or the system's: Android's back,
// Escape, the browser's) pops, iOS's drag from the left edge too. In a
// browser each screen is a URL (/fruit/3), kept by a reload.
class Navigation implements Markup {
	static final fruits = ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape", "Kiwi", "Lemon", "Mango", "Orange", "Pear"];
	static final compact = signal(false);

	static function main() {
		final nav = new Routes();
		nav.route("/", _ -> <List nav={nav}/>)
			.route("/fruit/:id", p -> <Detail nav={nav} id={Std.parseInt(p.id) ?? 0}/>)
			.route("/settings", _ -> <Settings nav={nav}/>)
			.fallback(path -> <Screen nav={nav} title="Not found"><text>{"Nothing at " + path}</text></Screen>);
		// (deep links: myapp://host/fruit/2)
		helder.os.App.onOpen = urls -> nav.open(urls[0]);
		UiWindow.run(<Surface title="Navigation" width={390} height={640}>
			<Stack router={nav}/>
		</Surface>);
	}

	static function Screen(props:{nav:Routes, title:String, ?root:Bool, ?action:View, children:View}):View
		return <view tag="page" flexGrow={1} background="#ffffff">
			<view flexDirection="row" alignItems="center" padding="10 12" columnGap={8} borderWidth="0 0 1 0" borderColor="#e4e4e7">
				{props.root != true ? <button tag="back" aria-label="Back" padding="6 10" borderRadius={6} cursor="pointer"
					onPress={() -> props.nav.back()}>‹ Back</button> : null}
				<text flexGrow={1} fontSize={18} fontWeight={600}>{props.title}</text>
				{props.action}
			</view>
			<scroll flexGrow={1} flexBasis={0} padding={12} rowGap={compact() ? 2 : 8}>{props.children}</scroll>
		</view>;

	static function List(props:{nav:Routes}):View {
		var nav = props.nav;
		return <Screen nav={nav} title="Fruit" root action={<button tag="settings" padding="6 10" borderRadius={6} cursor="pointer"
			onPress={() -> nav.go("/settings")}>Settings</button>}>
			{[for (i => f in fruits) <button tag={"fruit-" + i} padding={compact() ? "6 12" : "12 12"} borderRadius={8}
				background="#f4f4f5" cursor="pointer" onPress={() -> nav.go("/fruit/" + i)}>{f}</button>]}
		</Screen>;
	}

	static function Detail(props:{nav:Routes, id:Int}):View {
		var name = fruits[props.id] ?? "?", count = signal(0);
		return <Screen nav={props.nav} title={name}>
			<text fontSize={48}>{name.charAt(0)}</text>
			<text>{"Number " + (props.id + 1) + " of " + fruits.length + "."}</text>
			<button tag="like" padding="8 12" borderRadius={6} background="#18181b" color="#fafafa" cursor="pointer"
				onPress={() -> count(c -> c + 1)}>{"Liked " + count()}</button>
			{props.id + 1 < fruits.length ? <button tag="next" padding="8 12" borderRadius={6} background="#f4f4f5" cursor="pointer"
				onPress={() -> props.nav.go("/fruit/" + (props.id + 1))}>{"Next: " + fruits[props.id + 1]}</button> : null}
		</Screen>;
	}

	static function Settings(props:{nav:Routes}):View
		return <Screen nav={props.nav} title="Settings">
			<button tag="compact" role="switch" aria-checked={compact} flexDirection="row" padding="12 12" borderRadius={8} background="#f4f4f5"
				cursor="pointer" onPress={() -> compact(c -> !c)}>
				<text flexGrow={1}>Compact list</text>
				<text>{compact() ? "On" : "Off"}</text>
			</button>
			<button tag="home" padding="8 12" cursor="pointer" onPress={() -> props.nav.reset("/")}>Back to the list</button>
		</Screen>;
}
