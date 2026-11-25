# UI

helder's UI from TypeScript (TSX): `<view>` (a box, flex by default:
a column), `<text>`, `<image>`, `<scroll>`, `<field>`; attributes are
CSS-like (kebab-case), sizes in points. State is signals (`helder/view`):
an attribute or a hole that reads a signal follows it.

## Layout and style

```tsx file=card.tsx
export function Card(props: { title: string; note: string }) {
	return <view direction="row" align-items="center" column-gap={12} padding="12 16" radius={10}
		background="#ffffff" border-width={1} border-color="#e4e4e7">
		<view width={40} height={40} radius={20} background="#3b82f6"/>
		<view grow={1} row-gap={2}>
			<text font-size={15} font-weight={600} color="#18181b">{props.title}</text>
			<text font-size={13} color="#71717a" max-lines={2} text-overflow="ellipsis">{props.note}</text>
		</view>
	</view>;
}
```

Flex: `direction` (`column`, `row`), `grow`, `shrink`, `align-items`,
`justify` (`start`, `center`, `end`, `space-between`), `row-gap`,
`column-gap`, `wrap`. Boxes: `width`, `height`, `min-width`, `padding`
("12 16"), `radius`, `background`, `border-width`, `border-color`,
`opacity`, `overflow="hidden"`. Placed: `position="absolute"` with
`left`, `top`, `right`, `bottom`. Text: `font-size`, `font-weight`,
`color`, `text-align`, `max-lines`.

## State, lists, conditions, events

```tsx file=list.tsx
import { signal, For, Show } from "helder/view";
import { Event, Key } from "helder/ui";

export function List() {
	const items = signal<string[]>(["Milk", "Eggs"]);
	const draft = signal("");
	function add() {
		if (draft().trim() === "") return;
		items(l => l.concat([draft()]));
		draft("");
	}
	return <view padding={16} row-gap={8} background="#f8fafc" grow={1}>
		<view direction="row" column-gap={8}>
			<field grow={1} value={draft} placeholder="Add an item" label="Item" padding="8 12" radius={6}
				background="#ffffff" border-width={1} border-color="#e4e4e7"
				onInput={(e: Event) => draft(e.text)} onKeyDown={(e: Event) => { if (e.key === Key.ENTER) add(); }}/>
			<view:button role="button" focusable padding="8 12" radius={6} background="#18181b" color="#fafafa"
				cursor="pointer" onPress={() => add()}>Add</view:button>
		</view>
		<For each={items}>{item =>
			<text font-size={14} color="#18181b">{item()}</text>
		}</For>
		<Show when={() => items().length === 0}>
			<text color="#a1a1aa">Nothing yet</text>
		</Show>
		<text font-size={12} color="#71717a">{`${items().length} items`}</text>
	</view>;
}
```

- A view that takes its state as props (`Read` props take a value or a
  signal) can be posed by a story and run by the app alike.
- `signal(v)`: read `s()`, set `s(v)` or `s(old => new)`.
- `For each={signal}`: its child a function of each item (a `Read`: call it).
- `Show when={...}`: shown while true.
- Events: `onPress` (a `view:button`: a click, Enter or Space), `onClick`,
  `onPointerDown`/`Move`/`Up` (`e.x`, `e.y` in the window; `e.localX`,
  `e.localY` in the node), `onKeyDown`/`Up` (`e.key`: `Key.ENTER`, `Key.LEFT`,
  a letter's character code: `"a".charCodeAt(0)`), `onInput` (`e.text`).
