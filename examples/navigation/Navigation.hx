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
		return <view tag="page" grow={1} background="#ffffff">
			<view direction="row" align-items="center" padding="10 12" column-gap={8} border-width="0 0 1 0" border-color="#e4e4e7">
				{props.root != true ? <view:button tag="back" role="button" label="Back" focusable padding="6 10" radius={6} cursor="pointer"
					onPress={() -> props.nav.back()}>‹ Back</view:button> : null}
				<text grow={1} font-size={18} font-weight={600}>{props.title}</text>
				{props.action}
			</view>
			<scroll grow={1} basis={0} padding={12} row-gap={compact() ? 2 : 8}>{props.children}</scroll>
		</view>;

	static function List(props:{nav:Routes}):View {
		var nav = props.nav;
		return <Screen nav={nav} title="Fruit" root action={<view:button tag="settings" role="button" focusable padding="6 10" radius={6} cursor="pointer"
			onPress={() -> nav.go("/settings")}>Settings</view:button>}>
			{[for (i => f in fruits) <view:button tag={"fruit-" + i} role="button" focusable padding={compact() ? "6 12" : "12 12"} radius={8}
				background="#f4f4f5" cursor="pointer" onPress={() -> nav.go("/fruit/" + i)}>{f}</view:button>]}
		</Screen>;
	}

	static function Detail(props:{nav:Routes, id:Int}):View {
		var name = fruits[props.id] ?? "?", count = signal(0);
		return <Screen nav={props.nav} title={name}>
			<text font-size={48}>{name.charAt(0)}</text>
			<text>{"Number " + (props.id + 1) + " of " + fruits.length + "."}</text>
			<view:button tag="like" role="button" focusable padding="8 12" radius={6} background="#18181b" color="#fafafa" cursor="pointer"
				onPress={() -> count(c -> c + 1)}>{"Liked " + count()}</view:button>
			{props.id + 1 < fruits.length ? <view:button tag="next" role="button" focusable padding="8 12" radius={6} background="#f4f4f5" cursor="pointer"
				onPress={() -> props.nav.go("/fruit/" + (props.id + 1))}>{"Next: " + fruits[props.id + 1]}</view:button> : null}
		</Screen>;
	}

	static function Settings(props:{nav:Routes}):View
		return <Screen nav={props.nav} title="Settings">
			<view:button tag="compact" role="switch" checked={compact} focusable direction="row" padding="12 12" radius={8} background="#f4f4f5"
				cursor="pointer" onPress={() -> compact(c -> !c)}>
				<text grow={1}>Compact list</text>
				<text>{compact() ? "On" : "Off"}</text>
			</view:button>
			<view:button tag="home" role="button" focusable padding="8 12" cursor="pointer" onPress={() -> props.nav.reset("/")}>Back to the list</view:button>
		</Screen>;
}
