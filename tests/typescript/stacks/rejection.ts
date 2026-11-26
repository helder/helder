// a rejection no one handles: the program stops with the error's stack
async function check(n: number): Promise<number> {
	await null;
	if (n < 0) throw new RangeError("negative: " + n);
	return n;
}

async function main(): Promise<void> {
	console.log(await check(1));
	console.log(await check(-1));
}

main();
