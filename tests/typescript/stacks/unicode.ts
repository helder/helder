// columns in UTF-16 units, as V8 counts them: a string of astral characters
// before the throw
function where() {
	const s = "😀😀 é"; if (s.length > 0) throw new Error("after " + s);
}

try {
	where();
} catch (e) {
	console.log((e as Error).stack);
}
