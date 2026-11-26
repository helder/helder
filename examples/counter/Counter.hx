// title: Counter
// summary: The smallest ui program: a signal, markup bound to it, a button that changes it
// tags: ui, view, signals
// demo: canvas 320x200
import helder.view.*;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.graph.Graph.*;

// The README's example: a signal, markup bound to it, a button that changes it
// (a button: a view here, a <button> in a page; onPress a click, or Enter or Space)
class Counter implements Markup {
	static function main() {
		var count = signal(0);
		UiWindow.run(<Surface title="Counter" width={320} height={200}>
			<view flexGrow={1} padding={24} rowGap={12} alignItems="center" justifyContent="center">
				<text fontSize={32}>{count}</text>
				<button padding="8 16" borderRadius={6} background="#18181b" color="#fafafa" cursor="pointer"
					onPress={() -> count(c -> c + 1)}>+1</button>
			</view>
		</Surface>);
	}
}
