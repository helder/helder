# UI

helder's UI from TypeScript (TSX): `<view>` (a box, flex by default:
a column), `<text>`, `<image>`, `<scroll>`, `<field>`, and HTML's names
for what they mean (`<button>`, `<h2>`, `<p>`, `<a href>`, `<ul>`/`<li>`,
`<nav>`, `<textarea>`...); attributes are camel, as React Native writes
them: the style CSS's names (`flexDirection`, `alignItems`), sizes in
points; assistive technology's ARIA's (`aria-label`, `aria-checked`).
State is signals (`helder/view`): an attribute or a hole that reads a
signal follows it.

## Layout and style

```tsx file=card.tsx
export function Card(props: { title: string; note: string }) {
	return <view flexDirection="row" alignItems="center" columnGap={12} padding="12 16" borderRadius={10}
		background="#ffffff" borderWidth={1} borderColor="#e4e4e7">
		<view width={40} height={40} borderRadius={20} background="#3b82f6"/>
		<view flexGrow={1} rowGap={2}>
			<text fontSize={15} fontWeight={600} color="#18181b">{props.title}</text>
			<text fontSize={13} color="#71717a" lineClamp={2} textOverflow="ellipsis">{props.note}</text>
		</view>
	</view>;
}
```

Flex: `flexDirection` (`column`, `row`), `flexGrow`, `flexShrink`,
`alignItems`, `justifyContent` (`start`, `center`, `end`,
`space-between`), `rowGap`, `columnGap`, `flexWrap`. Boxes: `width`,
`height`, `minWidth`, `padding` ("12 16"), `borderRadius`, `background`,
`borderWidth`, `borderColor`, `opacity`, `overflow="hidden"`. Placed:
`position="absolute"` with `left`, `top`, `right`, `bottom`. Text:
`fontSize`, `fontWeight`, `fontStyle`, `color`, `textAlign`, `lineClamp`.

A box's shadow or glow: `shadow="0 8 24 rgba(0,0,0,0.15)"` (x, y, blur,
colour; several comma-separated; `0 0 16 #22d3ee` glows). It is the box's,
as CSS's box-shadow: on a `<text>` it lights the text's whole box. Glowing
text: `text-shadow="0 0 12 #22d3ee"` on the `<text>` (the letters' shapes,
blurred; `"0 0 4 #22d3ee, 0 0 16 #22d3ee"` for a stronger glow).

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
	return <view padding={16} rowGap={8} background="#f8fafc" flexGrow={1}>
		<view flexDirection="row" columnGap={8}>
			<field flexGrow={1} value={draft} placeholder="Add an item" aria-label="Item" padding="8 12" borderRadius={6}
				background="#ffffff" borderWidth={1} borderColor="#e4e4e7"
				onInput={(e: Event) => draft(e.text)} onKeyDown={(e: Event) => { if (e.key === Key.ENTER) add(); }}/>
			<button padding="8 12" borderRadius={6} background="#18181b" color="#fafafa"
				cursor="pointer" onPress={() => add()}>Add</button>
		</view>
		<For each={items}>{item =>
			<text fontSize={14} color="#18181b">{item()}</text>
		}</For>
		<Show when={() => items().length === 0}>
			<text color="#a1a1aa">Nothing yet</text>
		</Show>
		<text fontSize={12} color="#71717a">{`${items().length} items`}</text>
	</view>;
}
```

- The app's model in exported top-level signals: a scenario's `boot` sets
  them (`Read` props take a value or a signal).
- `signal(v)`: read `s()`, set `s(v)` or `s(old => new)`.
- `For each={signal}`: its child a function of each item (a `Read`: call it).
- `Show when={...}`: shown while true.
- Events: `onPress` (a `<button>`'s: a click, Enter or Space; a button
  takes the focus), `onPointerDown`/`Move`/`Up` (`e.x`, `e.y` in the window; `e.localX`,
  `e.localY` in the node), `onKeyDown`/`Up` (`e.key`: `Key.ENTER`, `Key.LEFT`,
  a letter's character code: `"a".charCodeAt(0)`), `onInput` (`e.text`).

## Data and dates

- HTTP: `Client.request(url, {method, headers, text})` from `helder/async`
  (there is no `fetch`): `await` it, then `res.status`, `res.text()`
  (`JSON.parse` it). A scenario's `boot` sets the data it shows; fetch
  only where the app runs it.
- `Date` works: `new Date()`, `Date.now()`, `getDay()`, `getDate()`,
  `getMonth()`, `getFullYear()`, `toISOString()`. Write day and month
  names yourself (no `Intl` or locale options).

```tsx file=today.tsx
import { Client } from "helder/async";

const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export async function temperature(): Promise<number> {
	const res = await Client.request("https://api.open-meteo.com/v1/forecast?latitude=51.05&longitude=3.72&current=temperature_2m");
	if (res.status !== 200) throw new Error(`forecast: ${res.status}`);
	return JSON.parse(res.text()).current.temperature_2m;
}

export function Today(props: { temp: number; date: Date }) {
	const d = props.date;
	return <view padding="16 20" borderRadius={12} background="#ffffff" boxShadow="0 8 24 rgba(0,0,0,0.12)" rowGap={4}>
		<text fontSize={13} color="#71717a">{`${days[d.getDay()]} ${d.getDate()}/${d.getMonth() + 1}`}</text>
		<text fontSize={32} fontWeight={600} color="#18181b">{`${Math.round(props.temp)}°`}</text>
	</view>;
}
```
