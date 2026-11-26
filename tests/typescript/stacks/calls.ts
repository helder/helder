// nested calls, recursion and closures: each error's stack, caught
function show(f: () => unknown) {
	try {
		f();
	} catch (e) {
		console.log((e as Error).stack);
	}
}

function deep(n: number): number {
	if (n === 0) throw new Error("bottom");
	return deep(n - 1) + 1;
}

function outer(): number[] {
	const inner = (x: number): number => {
		throw new Error("inner " + x);
	};
	return [1, 2].map(x => inner(x));
}

const counter = (() => {
	let n = 0;
	return function next(): number {
		if (++n > 1) throw new RangeError("twice");
		return n;
	};
})();

show(() => deep(3));
show(outer);
show(() => counter() + counter());
// (Error.stackTraceLimit's 10 frames)
show(() => deep(20));
