package viewer;

import helder.ui.Sheet;
import helder.ui.controls.Look;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A tablet's (Medium) browser, over the desktop's: the sidebar a drawer
// over the folder (the toolbar's button, a swipe from the left edge; a
// place chosen or the scrim pressed closes it), the inspector a sheet, a
// popover from the toolbar's Get Info button
class Tablet implements Markup {
	public static inline var DRAWER = 300;
	// (a swipe from within this of the left edge opens the drawer)
	static inline var EDGE = 20;

	public static function make(x:Explorer):View {
		var b = x.browser;
		// (another folder: the drawer done)
		var was = b.dir.value;
		effect(() -> b.dir(), d -> if (d != was) {
			was = d;
			x.sidebarOpen(false);
		});
		return <>
			<view tag="drawer-edge" position="absolute" left={0} top={0} bottom={0} width={EDGE} display={x.full() ? "none" : "flex"} pan-axis="x"
				onPan={g -> if (g.state == Ended && (g.tx > 40 || g.vx > 400)) x.sidebarOpen(true)}/>
			<Show when={x.sidebarOpen() && !x.full()}>
				<view tag="drawer-scrim" position="absolute" inset={0} background={Look.ref.scrim} transition="fade" onClick={_ -> x.sidebarOpen(false)}/>
				<view tag="drawer" slot="panel" position="absolute" left={0} top={0} bottom={0} width={DRAWER} padding="8 12 0 20"
					padding-top="calc(env(safe-area-inset-top) + 8px)" shadow="0 10px 40px rgba(0,0,0,0.3)" transition="fade slide-right" pan-axis="x"
					onPan={g -> if (g.state == Ended && (g.tx < -60 || g.vx < -400)) x.sidebarOpen(false)}>{SidebarView.make(x)}</view>
			</Show>
			<Sheet open={() -> x.infoOpen() && !x.full()} detents={[Medium, Large]} anchor={() -> x.infoAnchor} label="Info"
				onDismiss={() -> x.infoOpen(false)}>{InspectorView.make(x, true)}</Sheet>
		</>;
	}
}
