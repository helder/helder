// a value that is no error thrown and not caught: the value, and where it
// was thrown
function deep(n: number): void {
	if (n === 0) throw "the bottom";
	deep(n - 1);
}

setTimeout(() => deep(2), 0);
