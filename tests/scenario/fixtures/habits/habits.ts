export type Habit = { id: number; name: string; color: string; done: string[] };

export const palette = ["#22c55e", "#3b82f6", "#f97316", "#a855f7", "#ec4899", "#14b8a6"];
export const dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
export const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

function pad(n: number) { return n < 10 ? `0${n}` : `${n}`; }

export function dayKey(d: Date): string {
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function addDays(d: Date, n: number): Date {
	const r = new Date(d.getFullYear(), d.getMonth(), d.getDate());
	r.setDate(r.getDate() + n);
	return r;
}

/** The last `n` days ending with `today`, oldest first. */
export function lastDays(today: Date, n: number): Date[] {
	const out: Date[] = [];
	for (let i = n - 1; i >= 0; i--) out.push(addDays(today, -i));
	return out;
}

export function isDone(h: Habit, d: Date): boolean {
	return h.done.indexOf(dayKey(d)) >= 0;
}

/** Consecutive days done, ending today (or yesterday, while today is still open). */
export function streak(h: Habit, today: Date): number {
	let d = isDone(h, today) ? today : addDays(today, -1);
	let n = 0;
	while (isDone(h, d)) { n++; d = addDays(d, -1); }
	return n;
}

export function toggle(h: Habit, d: Date): Habit {
	const k = dayKey(d);
	const done = h.done.indexOf(k) >= 0 ? h.done.filter(x => x !== k) : h.done.concat([k]);
	return { id: h.id, name: h.name, color: h.color, done };
}

/** A sample week: each habit done on the days whose offset (0 = today) is in `pattern`. */
export function sample(today: Date): Habit[] {
	const make = (id: number, name: string, offsets: number[]): Habit =>
		({ id, name, color: palette[id % palette.length], done: offsets.map(o => dayKey(addDays(today, -o))) });
	return [
		make(0, "Drink 2L of water", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
		make(1, "Read 20 pages", [1, 2, 3, 5, 6]),
		make(2, "Morning run", [0, 2, 4, 6]),
		make(3, "Meditate", [0, 1, 2]),
		make(4, "No phone after 10pm", [3, 4]),
	];
}
