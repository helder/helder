package helder.ui.nav;

import helder.story.Story;
import helder.ui.Node;
import helder.ui.NavScreen;
import helder.ui.Sheet;
import helder.ui.Stack;
import helder.ui.menu.TouchMenu;
import helder.ui.view.UiFlow.VirtualGrid;
import helder.ui.view.UiView;
import helder.view.*;
import helder.view.graph.Graph.*;

// helder.ui's compact pieces in Look.base, at a phone's size: a stack's
// screen with its large title, the same scrolled (the title in the bar), a
// pushed screen (its back button, bar items, a bottom toolbar), a sheet at
// its medium detent, a long press's menu over its lifted preview, a grid in
// select mode; at a tablet's size, the sheet as a popover from its button
private final fruits = ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape", "Kiwi", "Lemon", "Mango", "Orange", "Pear", "Quince"];

final large = story({name: "Compact/large title", width: 390, height: 844, render: c -> stacked([])});

final scrolled = story({name: "Compact/scrolled", width: 390, height: 844, render: c -> stacked([], 160)});

final pushed = story({name: "Compact/pushed", width: 390, height: 844, render: c -> stacked(["/fruit/2"])});

final sheet = story({
	name: "Compact/sheet, medium",
	width: 390,
	height: 844,
	render: c -> <view grow={1}>
		{stacked([])}
		<Sheet open={true} detents={[Medium, Large]} label="Details"><Details/></Sheet>
	</view>
});

final menu = story({name: "Compact/long press menu", width: 390, height: 844, render: c -> <Pressed/>});

final select = story({name: "Compact/select mode", width: 390, height: 844, render: c -> <Selecting/>});

final popover = story({
	name: "Medium/sheet as a popover",
	width: 820,
	height: 1180,
	render: c -> {
		var button:Null<Node> = null;
		<view grow={1}>
			<NavScreen title="Fruit" trailing={<view ref={n -> button = n}><NavButton label="Info" onPress={() -> {}}/></view>}><Rows/></NavScreen>
			<Sheet open={true} anchor={() -> button} label="Details"><Details/></Sheet>
		</view>;
	}
});

// (a stack at the root's list, the paths pushed over it; the root scrolled by y)
private function stacked(paths:Array<String>, y = 0.0):View {
	var nav = new Router();
	nav.route("/", _ -> <NavScreen title="Fruit" large subtitle={fruits.length + " kinds"} header={<Search/>}
		trailing={<NavButton label="Select" onPress={() -> {}}/>}><Rows y={y}/></NavScreen>)
		.route("/fruit/:id", p -> {
			var name = fruits[Std.parseInt(p.id) ?? 0];
			<NavScreen title={name} trailing={<NavButton label="Share" onPress={() -> {}}/>} bottom={<Toolbar/>}>
				<view padding={16} row-gap={12}><text font-size={48}>{name.charAt(0)}</text><text>{"A " + name.toLowerCase() + "."}</text></view>
			</NavScreen>;
		});
	for (p in paths)
		nav.go(p);
	return <Stack router={nav} transition={None}/>;
}

private function Search(props:{}):UiView
	return <view direction="row" align-items="center" column-gap={7} height={38} margin="0 16 12" padding="0 10" radius={11} background="#e9e9eb" color="#6c6c6c">
		<text>Search</text>
	</view>;

private function Rows(props:{?y:Float}):UiView {
	var nav = use(Bar.here);
	// (once laid out: a scroller clamps an offset past its content)
	if (props.y != null && props.y > 0) onSettled(() -> Clock.after(0.01, () -> nav.scrollTo(props.y)));
	return <view>
		{[for (f in fruits) <view direction="row" align-items="center" height={50} padding="0 16" shrink={0}><text>{f}</text></view>]}
	</view>;
}

private function Toolbar(props:{}):UiView
	return <view direction="row" justify="space-between" padding="6 12">
		<NavButton label="Open in…" onPress={() -> {}}/>
		<NavButton label="Info" onPress={() -> {}}/>
		<NavButton label="Trash" onPress={() -> {}}/>
	</view>;

private function Details(props:{}):UiView
	return <view padding="6 16" row-gap={8}>
		<text font-size={17} font-weight={600}>Cherry</text>
		<text font-size={13}>A stone fruit, picked in June.</text>
	</view>;

// (a tile, its menu open over its preview)
private function Pressed(props:{}):UiView {
	var tile:Null<Node> = null;
	onSettled(() -> Clock.after(0.01, () -> if (tile != null && tile.ui != null) {
		var t = tile;
		TouchMenu.open(t.ui, [
			{label: "Open", run: () -> {}},
			{label: "Get Info", run: () -> {}},
			{label: "Select", run: () -> {}},
			{label: "Move to Trash", destructive: true, separated: true, run: () -> {}}
		], t.windowBounds(), <view grow={1} background="#e3a64b"/>, true, t.sheet());
	}));
	return <NavScreen title="Fruit" large>
		<view direction="row" padding="4 16" column-gap={10}>
			{[for (k in 0...3) <view tag={"tile-" + k} grow={1} basis={0} aspect-ratio={1} radius={9} background={["#c94f4f", "#e3a64b", "#6fa35b"][k]}
				ref={n -> if (k == 1) tile = n}/>]}
		</view>
	</NavScreen>;
}

private function Selecting(props:{}):UiView
	return <NavScreen title="Select Items" scrolls={false} trailing={<NavButton label="Done" onPress={() -> {}}/>} bottom={<Toolbar/>}><Picked/></NavScreen>;

// (the grid, the screen's scroller, three picked)
private function Picked(props:{}):UiView {
	var nav = use(Bar.here), grid:Null<helder.ui.GridScroll> = null;
	onSettled(() -> if (grid != null) grid.selection.setKeys(["Banana", "Date", "Fig"]));
	return <VirtualGrid each={fruits} by={f -> f} cellWidth={110} cellHeight={130} selectMode={true} ref={g -> {
		grid = g;
		if (nav != null) nav.scroller(g);
	}}>{(f, i) -> {
		var on = () -> grid != null && grid.selection.version() >= 0 && grid.selection.has(f());
		<view grow={1} padding={4} row-gap={4} align-items="center">
			<view width="100%" aspect-ratio={1} radius={9} background="#d4d4d4" border-width={on() ? 2.5 : 0} border-color="#1d1d1d"/>
			<text font-size={13}>{f()}</text>
		</view>;
	}}</VirtualGrid>;
}
