// title: Counter in TypeScript
// summary: The counter in TSX: a signal, markup bound to it, a button that changes it
// tags: typescript, ui, view, signals
// demo: canvas 320x200
// The counter in TypeScript: a signal, TSX bound to it, a button that changes it.
import { signal } from "helder/view";
import { UiWindow, Surface } from "helder/ui";

const count = signal(0);

UiWindow.run(
	<Surface title="Counter" width={320} height={200}>
		<view flexGrow={1} padding={24} rowGap={12} alignItems="center" justifyContent="center">
			<text fontSize={32}>{count}</text>
			<button padding="8 16" borderRadius={6} background="#18181b" color="#fafafa" cursor="pointer"
				onPress={() => count(c => c + 1)}>+1</button>
		</view>
	</Surface>
);
