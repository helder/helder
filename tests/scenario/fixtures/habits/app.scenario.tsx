import { scenario } from "helder/scenario";
import { sample, toggle, isDone } from "./habits";

// main.tsx as it starts on the morning of 26 November, its habits set by name
const day = new Date(2026, 10, 26);
const time = "2026-11-26T09:00";

export const today = scenario({ name: "Habits/Today", time });
export const allDone = scenario({ name: "Habits/All done", time,
	set: { "App.habits": sample(day).map(h => isDone(h, day) ? h : toggle(h, day)) } });
export const empty = scenario({ name: "Habits/Empty", time, set: { "App.habits": [] } });
