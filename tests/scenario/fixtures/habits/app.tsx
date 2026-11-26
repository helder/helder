import { signal, For, Show } from "helder/view";
import { Event, Key } from "helder/ui";
import { Habit, dayNames, monthNames, lastDays, isDone, streak, toggle, palette } from "./habits";

const ink = "#18181b";
const muted = "#71717a";
const faint = "#e4e4e7";
const bg = "#f4f4f5";

function HabitRow(props: { habit: Habit; today: Date; onToggle: () => void }) {
	const h = props.habit;
	const done = isDone(h, props.today);
	const s = streak(h, props.today);
	return <view direction="row" align-items="center" column-gap={14} padding="14 16" radius={14}
		background="#ffffff" shadow="0 1 3 rgba(0,0,0,0.06)">
		<view width={6} height={40} radius={3} background={h.color}/>
		<view grow={1} shrink={1} row-gap={8}>
			<view row-gap={2}>
				<text font-size={16} font-weight={600} color={ink} max-lines={1} text-overflow="ellipsis">{h.name}</text>
				<text font-size={12} color={s > 0 ? h.color : muted} font-weight={s > 0 ? 600 : 400}>
					{s > 0 ? `${s}-day streak` : "No streak yet"}
				</text>
			</view>
			<view direction="row" column-gap={4}>
				{lastDays(props.today, 7).map(d =>
					<view width={18} height={6} radius={3} background={isDone(h, d) ? h.color : faint}/>)}
			</view>
		</view>
		<view:button role="button" focusable label={done ? `Undo ${h.name}` : `Done ${h.name}`}
			width={36} height={36} radius={18} align-items="center" justify="center" cursor="pointer"
			background={done ? h.color : "#ffffff"} border-width={2} border-color={done ? h.color : "#d4d4d8"}
			onPress={() => props.onToggle()}>
			<text font-size={18} font-weight={700} color={done ? "#ffffff" : "#ffffff"}>✓</text>
		</view:button>
	</view>;
}

export function App(props: { habits?: Habit[]; today?: Date }) {
	const today = props.today ?? new Date();
	const habits = signal<Habit[]>(props.habits ?? []);
	const draft = signal("");

	// (the model is App.habits and App.draft: the next id comes from them, not a counter)
	function add() {
		const name = draft().trim();
		if (name === "") return;
		const id = habits().reduce((m, h) => Math.max(m, h.id + 1), 100);
		habits(l => l.concat([{ id, name, color: palette[l.length % palette.length], done: [] }]));
		draft("");
	}

	const doneCount = () => habits().filter(h => isDone(h, today)).length;
	const progress = () => habits().length === 0 ? 0 : doneCount() / habits().length;

	return <view grow={1} background={bg} padding="56 20 24 20" row-gap={20}>
		<view row-gap={4}>
			<text font-size={14} color={muted}>{`${dayNames[today.getDay()]}, ${monthNames[today.getMonth()]} ${today.getDate()}`}</text>
			<text font-size={32} font-weight={700} color={ink}>Today</text>
		</view>

		<Show when={() => habits().length > 0}>
		<view padding="16 18" radius={16} background={ink} row-gap={10}>
			<view direction="row" justify="space-between" align-items="end">
				<text font-size={15} font-weight={600} color="#fafafa">
					{() => progress() === 1 ? "All done. Nice work!" : "Keep it going"}
				</text>
				<text font-size={13} color="#a1a1aa">{() => `${doneCount()} of ${habits().length}`}</text>
			</view>
			<view height={8} radius={4} background="#3f3f46" overflow="hidden" direction="row">
				<view width={() => `${Math.round(progress() * 100)}%`} height={8} radius={4} background="#22c55e"/>
			</view>
		</view>
		</Show>

		<scroll grow={1} shrink={1}>
			<view row-gap={10}>
				<For each={habits}>{h =>
					<HabitRow habit={h()} today={today}
						onToggle={() => habits(l => l.map(x => x.id === h().id ? toggle(x, today) : x))}/>
				}</For>
				<Show when={() => habits().length === 0}>
					<view padding="40 20" align-items="center" row-gap={6}>
						<text font-size={16} font-weight={600} color={ink}>No habits yet</text>
						<text font-size={14} color={muted} text-align="center">Add one below. Small and daily works best.</text>
					</view>
				</Show>
			</view>
		</scroll>

		<view direction="row" column-gap={8}>
			<field grow={1} value={draft} placeholder="New habit, e.g. Stretch 5 min" label="New habit" padding="12 14" radius={12}
				background="#ffffff" border-width={1} border-color={faint} font-size={15}
				onInput={(e: Event) => draft(e.text)} onKeyDown={(e: Event) => { if (e.key === Key.ENTER) add(); }}/>
			<view:button role="button" focusable padding="12 18" radius={12} background={ink} cursor="pointer"
				align-items="center" justify="center" onPress={() => add()}>
				<text font-size={15} font-weight={600} color="#fafafa">Add</text>
			</view:button>
		</view>
	</view>;
}
