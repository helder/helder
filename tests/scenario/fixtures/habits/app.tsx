import { signal, For, Show, Signal } from "helder/view";
import { Event, Key } from "helder/ui";
import { Habit, dayNames, monthNames, lastDays, isDone, streak, toggle, palette, sample } from "./habits";

const ink = "#18181b";
const muted = "#71717a";
const faint = "#e4e4e7";
const bg = "#f4f4f5";

function HabitRow(props: { habit: Habit; today: Date; onToggle: () => void }) {
	const h = props.habit;
	const done = isDone(h, props.today);
	const s = streak(h, props.today);
	return <view flexDirection="row" alignItems="center" columnGap={14} padding="14 16" borderRadius={14}
		background="#ffffff" shadows={[{x: 0, y: 1, blur: 3, color: 0x0F000000}]}>
		<view width={6} height={40} borderRadius={3} background={h.color}/>
		<view flexGrow={1} flexShrink={1} rowGap={8}>
			<view rowGap={2}>
				<text fontSize={16} fontWeight={600} color={ink} lineClamp={1} textOverflow="ellipsis">{h.name}</text>
				<text fontSize={12} color={s > 0 ? h.color : muted} fontWeight={s > 0 ? 600 : 400}>
					{s > 0 ? `${s}-day streak` : "No streak yet"}
				</text>
			</view>
			<view flexDirection="row" columnGap={4}>
				{lastDays(props.today, 7).map(d =>
					<view width={18} height={6} borderRadius={3} background={isDone(h, d) ? h.color : faint}/>)}
			</view>
		</view>
		<button aria-label={done ? `Undo ${h.name}` : `Done ${h.name}`}
			width={36} height={36} borderRadius={18} alignItems="center" justifyContent="center" cursor="pointer"
			background={done ? h.color : "#ffffff"} borderWidth={2} borderColor={done ? h.color : "#d4d4d8"}
			onPress={() => props.onToggle()}>
			<text fontSize={18} fontWeight={700} color={done ? "#ffffff" : "#ffffff"}>✓</text>
		</button>
	</view>;
}

// the app's model: its habits and the field's text (a scenario's boot writes them)
export const model = signal<Habit[]>(sample(new Date()));
export const draft = signal("");

// (the next id comes from the habits, not a counter)
function added(list: Signal<Habit[]>, name: string) {
	const id = list().reduce((m, h) => Math.max(m, h.id + 1), 100);
	list(l => l.concat([{ id, name, color: palette[l.length % palette.length], done: [] }]));
}

export function addHabit(name: string) {
	added(model, name);
}

// the habit of that name done (or not) on a day
export function check(name: string, day: Date) {
	model(l => l.map(h => h.name === name ? toggle(h, day) : h));
}

export function App(props: { habits?: Habit[]; today?: Date }) {
	const today = props.today ?? new Date();
	// (a story's habits posed, else the app's)
	const habits = props.habits ? signal(props.habits) : model;
	function add() {
		const name = draft().trim();
		if (name === "") return;
		added(habits, name);
		draft("");
	}

	const doneCount = () => habits().filter(h => isDone(h, today)).length;
	const progress = () => habits().length === 0 ? 0 : doneCount() / habits().length;

	return <view flexGrow={1} background={bg} padding="56 20 24 20" rowGap={20}>
		<view rowGap={4}>
			<text fontSize={14} color={muted}>{`${dayNames[today.getDay()]}, ${monthNames[today.getMonth()]} ${today.getDate()}`}</text>
			<text fontSize={32} fontWeight={700} color={ink}>Today</text>
		</view>

		<Show when={() => habits().length > 0}>
		<view padding="16 18" borderRadius={16} background={ink} rowGap={10}>
			<view flexDirection="row" justifyContent="space-between" alignItems="end">
				<text fontSize={15} fontWeight={600} color="#fafafa">
					{() => progress() === 1 ? "All done. Nice work!" : "Keep it going"}
				</text>
				<text fontSize={13} color="#a1a1aa">{() => `${doneCount()} of ${habits().length}`}</text>
			</view>
			<view height={8} borderRadius={4} background="#3f3f46" overflow="hidden" flexDirection="row">
				<view width={() => `${Math.round(progress() * 100)}%`} height={8} borderRadius={4} background="#22c55e"/>
			</view>
		</view>
		</Show>

		<scroll flexGrow={1} flexShrink={1}>
			<view rowGap={10}>
				<For each={habits}>{h =>
					<HabitRow habit={h()} today={today}
						onToggle={() => habits(l => l.map(x => x.id === h().id ? toggle(x, today) : x))}/>
				}</For>
				<Show when={() => habits().length === 0}>
					<view padding="40 20" alignItems="center" rowGap={6}>
						<text fontSize={16} fontWeight={600} color={ink}>No habits yet</text>
						<text fontSize={14} color={muted} textAlign="center">Add one below. Small and daily works best.</text>
					</view>
				</Show>
			</view>
		</scroll>

		<view flexDirection="row" columnGap={8}>
			<field flexGrow={1} value={draft} placeholder="New habit, e.g. Stretch 5 min" aria-label="New habit" padding="12 14" borderRadius={12}
				background="#ffffff" borderWidth={1} borderColor={faint} fontSize={15}
				onInput={(e: Event) => draft(e.text)} onKeyDown={(e: Event) => { if (e.key === Key.ENTER) add(); }}/>
			<button padding="12 18" borderRadius={12} background={ink} cursor="pointer"
				alignItems="center" justifyContent="center" onPress={() => add()}>
				<text fontSize={15} fontWeight={600} color="#fafafa">Add</text>
			</button>
		</view>
	</view>;
}
