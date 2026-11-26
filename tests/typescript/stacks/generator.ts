// a generator's body throwing, run by its caller's for-of
function* numbers(limit: number) {
	for (let i = 0; i < 10; i++) {
		if (i === limit) throw new Error("past " + limit);
		yield i;
	}
}

function sum(limit: number): number {
	let s = 0;
	for (const n of numbers(limit)) s += n;
	return s;
}

try {
	console.log(sum(3));
} catch (e) {
	console.log((e as Error).stack);
}
