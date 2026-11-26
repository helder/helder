// errors the runtime throws: a property read of null, an element of
// undefined. (A direct function small enough to be inlined into its caller
// has no frame of its own: hxmc names the copy's code by the call's place;
// `last`, its property read a site's check and the site's stub, is not.)
function show(f: () => unknown) {
	try {
		f();
	} catch (e) {
		console.log((e as Error).stack);
	}
}

type Item = {next: Item | null; value: number};

function last(n: Item): number {
	let at: any = n;
	while (true) at = at.next;
}

function first(items: any) {
	const row = items[0];
	return row[0];
}

show(() => last({next: {next: null, value: 2}, value: 1}));
show(() => first([undefined]));
show(() => [1, 2, 3].reduce((a, b) => {
	if (b === 3) return (null as any).total;
	return a + b;
}));
