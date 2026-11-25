// title: A million rows in TypeScript
// summary: VirtualList from TSX over a million rows of their own heights: scrolled, jumped to the end, the keyboard, rows put in above without a move
// tags: typescript, ui, view, virtual list
// demo: canvas 480x640
// examples/million in TypeScript: a million messages in a VirtualList
// (helder/ui), only the rows in view made, each as tall as its text wraps,
// the scroll anchored to the row at the top. The toolbar jumps to the top,
// the middle and the end and puts three rows in above the first in view;
// the keyboard moves the selection onto rows not made yet. The same script
// drives both headless (tests/headless/million.json).
import { signal, untrack, Read, Signal } from "helder/view";
import { UiWindow, Surface, VirtualList, VirtualScroll } from "helder/ui";

const COUNT = 1000000;
const NAMES = ["Ada", "Grace", "Linus", "Margaret", "Ken", "Barbara", "Dennis", "Frances", "Alan", "Radia", "Edsger", "Hedy"];
const COLORS = ["#ef4444", "#f97316", "#eab308", "#22c55e", "#14b8a6", "#3b82f6", "#6366f1", "#a855f7", "#ec4899", "#64748b"];
const SENTENCES = [
	"Only the rows in view are made.", "The others are a number each in a sum tree of heights.", "Scrolling a million rows costs what twenty do.",
	"Each row is measured the first time it is shown.", "Until then its height is the estimate.", "The scroll stays on the row at the top.",
	"Rows put in above it move nothing.", "End jumps to the last row, made and measured on the way.", "The arrow keys walk onto rows not made yet.",
	"A row that leaves the view is kept for a while.", "Coming back to it makes nothing new.", "Selection is a key, so it outlives its row's node."
];

function hash(i: number): number {
	let h = Math.imul(i, 0x45d9f3b);
	h = Math.imul(h ^ (h >>> 16), 0x45d9f3b);
	return (h ^ (h >>> 16)) & 0x7fffffff;
}

// (a day's header every 200 rows)
const isDay = (id: number) => id < COUNT && id % 200 === 0;
const author = (id: number) => id >= COUNT ? "New" : NAMES[hash(id) % NAMES.length];

// a message of one to six sentences (one line to four)
function message(id: number): string {
	if (id >= COUNT) return "Put in above the first row in view.";
	const h = hash(id + 7), n = 1 + (h % 4 === 0 ? h % 6 : h % 2), out: string[] = [];
	for (let k = 0; k < n; k++) out.push(SENTENCES[(h + k * 5) % SENTENCES.length]);
	return out.join(" ");
}

function thousands(n: number): string {
	let s = String(n), out = "";
	while (s.length > 3) {
		out = "," + s.substring(s.length - 3) + out;
		s = s.substring(0, s.length - 3);
	}
	return s + out;
}

const ids: number[] = [];
for (let i = 0; i < COUNT; i++) ids.push(i);
const items = signal(ids);
const selected = signal<any>(null);
let list: VirtualScroll | null = null;
let added = COUNT;

// three rows put in before the first in view: it stays where it is
function insertAbove() {
	const at = Math.max(0, list ? list.firstVisible() : 0);
	const next = items().slice();
	for (let k = 0; k < 3; k++) next.splice(at, 0, added++);
	items(next);
}

function Button(props: { tag: string; label: string; onPress: () => void }) {
	return <button tag={props.tag} cursor="pointer" padding="4 10" borderRadius={6} background="#18181b" color="#fafafa"
		onPress={() => props.onPress()}>{props.label}</button>;
}

// a row: a day's header, or a message (its author's initial, name and number, its text)
function Row(props: { id: Read<number> }) {
	const id = untrack(() => props.id());
	if (isDay(id))
		return <view tag="day" padding="6 16" background="#f4f4f5">
			<text fontSize={11} fontWeight={700} color="#71717a">{"Day " + thousands((id / 200 | 0) + 1)}</text>
		</view>;
	const name = author(id);
	return <view tag="message" flexDirection="row" columnGap={10} padding="8 16" background={selected() === id ? "#dbeafe" : "#ffffff"}>
		<view width={32} height={32} borderRadius={16} flexShrink={0} background={id >= COUNT ? "#18181b" : COLORS[hash(id + 3) % COLORS.length]} alignItems="center"
			justifyContent="center"><text color="#ffffff" fontWeight={700}>{name.charAt(0)}</text></view>
		<view flexGrow={1} flexShrink={1} minWidth={0} rowGap={2}>
			<view flexDirection="row" columnGap={6}><text fontWeight={700}>{name}</text><text color="#a1a1aa">{"#" + thousands(id)}</text></view>
			<text color="#3f3f46">{message(id)}</text>
		</view>
	</view>;
}

function App() {
	return <view flexGrow={1} background="#fafafa" fontSize={13} color="#18181b">
		<view tag="toolbar" flexDirection="row" alignItems="center" columnGap={6} padding="8 12" background="#ffffff">
			<text tag="title" flexGrow={1} fontWeight={700}>A million rows</text>
			<Button tag="top" label="Top" onPress={() => { if (list) list.focusIndex(0); }}/>
			<Button tag="middle" label="Middle" onPress={() => { if (list) list.scrollToIndex(items().length / 2 | 0, "start"); }}/>
			<Button tag="end" label="End" onPress={() => { if (list) list.focusIndex(items().length - 1); }}/>
			<Button tag="insert" label="Insert" onPress={insertAbove}/>
		</view>
		<VirtualList tag="rows" each={items} estimate={52} selected={selected as Signal<any>} label="Messages" ref={(l: VirtualScroll) => { list = l; }}>{
			(id: Read<number>, i: number) => <Row id={id}/>}</VirtualList>
		<view tag="status" flexDirection="row" padding="6 12" background="#ffffff">
			<text tag="status-text" color="#71717a">{thousands(items().length) + " rows" + (selected() === null ? "" : " · #" + thousands(selected()) + " selected")}</text>
		</view>
	</view>;
}

UiWindow.run(
	<Surface title="A million rows" width={480} height={640}>
		<App/>
	</Surface>
);
