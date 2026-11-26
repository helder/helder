// async functions awaiting each other: the frames of those waiting, as V8's
// async stack traces have them
async function load(id: number): Promise<number> {
	await null;
	if (id > 2) throw new Error("no item " + id);
	return id;
}

async function total(ids: number[]): Promise<number> {
	let sum = 0;
	for (const id of ids) sum += await load(id);
	return sum;
}

async function report(): Promise<void> {
	const n = await total([1, 2, 3]);
	console.log(n);
}

report().catch(e => console.log(e.stack));

async function first(): Promise<void> {
	throw new TypeError("before any await");
}

async function caller(): Promise<void> {
	await first();
}

caller().catch(e => console.log(e.stack));
