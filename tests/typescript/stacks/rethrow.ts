// a caught error thrown again keeps where it was made, across awaits too
function fail(what: string): never {
	throw new Error(what);
}

function again() {
	try {
		fail("first");
	} catch (e) {
		throw e;
	}
}

try {
	again();
} catch (e) {
	console.log((e as Error).stack);
}

async function later(): Promise<void> {
	await null;
	fail("later");
}

async function wrap(): Promise<void> {
	try {
		await later();
	} catch (e) {
		await null;
		throw e;
	}
}

wrap().catch(e => console.log(e.stack));
