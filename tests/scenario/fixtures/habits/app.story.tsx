import { story } from "helder/story";
import { App } from "./app";
import { sample, toggle, isDone } from "./habits";

export const today = story({ name: "Habit list/Today", render: () => {
	const d = new Date(2026, 10, 26);
	return <App today={d} habits={sample(d)}/>;
} });

export const allDone = story({ name: "Habit list/All done", render: () => {
	const d = new Date(2026, 10, 26);
	return <App today={d} habits={sample(d).map(h => isDone(h, d) ? h : toggle(h, d))}/>;
} });

export const empty = story({ name: "Habit list/Empty", render: () => <App today={new Date(2026, 10, 26)} habits={[]}/> });
