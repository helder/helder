// The todo list's view: a store's signals hold the state (todos.ts changes
// it; the program's, or a story's own), For keeps a row per item (by its
// id), the text field adds one on Enter, the checkboxes and the filters
// update what is shown. Its buttons and checkboxes are components of its
// own (TypeScript functions), styled inline; a hole or an attribute that
// reads follows what it reads, as in Haxe (a filter's outline: a Read
// prop). The filters have shortcuts: Todo's actions (helder/ui/actions:
// todo::Show in a JSON keymap), bound to secondary-1, -2 and -3 and handled
// by the view's root, from anywhere in it, the text field too. main.tsx
// shows it in a window, app.test.tsx mounts it headless.
import { signal, memo, For, Show, Read, Signal } from "helder/view";
import { Event, Key } from "helder/ui";
import { actions, handle, Keymap } from "helder/ui/actions";
import { Item, added, removed, toggled, shown, left } from "./todos";

// a list's state: the program's (main.tsx's, the tests'), or a story's own (app.story.tsx: one program shows every story)
export type Store = { todos: Signal<Item[]>; nextId: Signal<number>; draft: Signal<string>; filter: Signal<string> };
export function store(list: Item[] = [], show = "all"): Store {
	return { todos: signal<Item[]>(list), nextId: signal(list.length + 1), draft: signal(""), filter: signal(show) };
}
const main = store();
export const todos = main.todos;
export const draft = main.draft;
export const filter = main.filter;
export const Todo = actions("todo", { show(filter: string) { return { filter }; } });
Keymap.global.bind("secondary-1", Todo.show("all")).bind("secondary-2", Todo.show("active")).bind("secondary-3", Todo.show("done"));

export function add(s: Store = main) {
	if (s.draft().trim() === "") return;
	s.todos(added(s.todos(), s.nextId(), s.draft()));
	s.nextId(n => n + 1);
	s.draft("");
}

function Button(props: { label: string; onPress: () => void; tag?: string; outline?: Read<boolean>; small?: boolean }) {
	return <button tag={props.tag ?? "button"} cursor="pointer" flexDirection="row" alignItems="center" justifyContent="center"
		padding={props.small ? "4 8" : "6 12"} borderRadius={6} borderWidth={props.outline?.() ? 1 : 0} borderColor="#e4e4e7"
		background={props.outline?.() ? "#ffffff" : "#18181b"} color={props.outline?.() ? "#18181b" : "#fafafa"}
		onPress={() => props.onPress()}>{props.label}</button>;
}

// (the label pressed toggles it too)
function Checkbox(props: { checked: Read<boolean>; label: Read<string>; onToggle: () => void }) {
	return <view flexDirection="row" alignItems="center" columnGap={8}>
		<button role="checkbox" aria-label={props.label()} aria-checked={props.checked()} cursor="pointer" width={16} height={16} borderRadius={4}
			borderWidth={1} alignItems="center" justifyContent="center" borderColor={props.checked() ? "#18181b" : "#a1a1aa"}
			background={props.checked() ? "#18181b" : "#ffffff"} onPress={() => props.onToggle()}>
			<Show when={props.checked}><icon name="check" width={12} height={12} color="#fafafa"/></Show>
		</button>
		<text aria-hidden cursor="pointer" color={props.checked() ? "#a1a1aa" : "#18181b"}
			textDecoration={props.checked() ? "line-through" : "none"} onPress={() => props.onToggle()}>{props.label()}</text>
	</view>;
}

// (its store: a story's, else the program's)
export function App(props: { store?: Store }) {
	const s = props?.store ?? main, remaining = memo(() => left(s.todos()));
	const visible = () => shown(s.todos(), s.filter());
	return <view flexGrow={1} padding={24} rowGap={14} background="#fafafa" fontSize={14} color="#18181b"
		actions={handle(Todo, a => {
			switch (a.type) {
				case "show":
					s.filter(a.filter);
					return true;
			}
		})}>
		<text fontSize={28} fontWeight={700} color="#3b82f6">todos</text>
		<view flexDirection="row" columnGap={8}>
			<field tag="draft" flexGrow={1} value={s.draft} placeholder="What needs to be done?" aria-label="What needs to be done?" padding="8 12" borderRadius={6}
				borderWidth={1} borderColor="#e4e4e7" background="#ffffff"
				onInput={(e: Event) => s.draft(e.text)} onKeyDown={(e: Event) => { if (e.key === Key.ENTER) add(s); }}/>
			<Button tag="add" label="Add" onPress={() => add(s)}/>
		</view>
		<scroll tag="list" flexGrow={1} minHeight={0} rowGap={6} background="#ffffff" borderRadius={8} borderWidth={1} borderColor="#e4e4e7" padding={8}>
			<For each={visible} by={i => i.id}>{item => <view flexDirection="row" alignItems="center" columnGap={8} padding="4 6" borderRadius={6}>
				<view flexGrow={1}><Checkbox checked={() => item().done} label={() => item().title} onToggle={() => s.todos(toggled(s.todos(), item().id))}/></view>
				<Button label="Remove" outline small onPress={() => s.todos(removed(s.todos(), item().id))}/>
			</view>}</For>
			<Show when={visible().length === 0}><text color="#a1a1aa" padding={6}>Nothing here.</text></Show>
		</scroll>
		<view flexDirection="row" alignItems="center" justifyContent="space-between">
			<text tag="left">{remaining()}</text>
			<view flexDirection="row" columnGap={6}>{["all", "active", "done"].map(f =>
				<Button tag={"filter-" + f} label={f} outline={s.filter() !== f} small onPress={() => s.filter(f)}/>)}</view>
		</view>
	</view>;
}
