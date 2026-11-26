// a value that is no error, caught and thrown again in a timer's callback:
// where it was thrown last, whatever the runtime's catches between (a timer
// runs in the store that set it, Promises.inStore)
function deep(n: number): void {
	if (n === 0) throw 42;
	deep(n - 1);
}

function again() {
	try {
		deep(1);
	} catch (e) {
		throw e;
	}
}

setTimeout(() => again(), 0);
