import { scenario, tap, type } from "helder/scenario";
import { model, addHabit, check } from "./app";
import { sample, toggle, isDone } from "./habits";

// the app on the morning of 26 November: boot writes its model, or calls its own functions
const day = new Date(2026, 10, 26);
const time = "2026-11-26T09:00";

export const today = scenario({ name: "Habits/Today", time, boot() { model(sample(day)); } });
export const allDone = scenario({ name: "Habits/All done", time, boot() { model(sample(day).map(h => isDone(h, day) ? h : toggle(h, day))); } });
export const empty = scenario({ name: "Habits/Empty", time, boot() { model([]); } });
export const added = scenario({ name: "Habits/Added", time, boot() { model([]); addHabit("Read"); check("Read", day); } });

// the same moments reached as a user would: steps after boot
export const allDoneByHand = scenario({ name: "Habits/All done, by hand", time, boot() { model(sample(day)); },
	steps: [tap("Done Read 20 pages"), tap("Done No phone after 10pm")] });
export const addedByHand = scenario({ name: "Habits/Added, by hand", time, boot() { model([]); },
	steps: [type("New habit", "Read"), tap("Add"), tap("Done Read")] });
