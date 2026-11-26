// A VirtualList's selected holds a key of its rows (by's): a signal of
// another type is an error.
// expect: VirtualListKey.hx:11: characters 54-62
// expect: String should be Int
import helder.ui.view.UiFlow.*;

class VirtualListKey implements helder.view.Markup {
	static function main() {
		var rows = [{id: 1, name: "a"}], selected = helder.view.graph.Graph.signal((null : Null<String>));
		helder.view.Render.render(<view>
			<VirtualList each={rows} by={r -> r.id} selected={selected}>{(r, i) -> <text>{r().name}</text>}</VirtualList>
		</view>, new helder.ui.Node());
	}
}
