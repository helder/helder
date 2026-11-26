// Error.stackTraceLimit, and Error.captureStackTrace's stack of an object
// (declared for tsc, as node's types do: helder's globals.d.ts has them)
export {};

declare global {
	interface ErrorConstructor {
		captureStackTrace(target: object): void;
		stackTraceLimit: number;
	}
}

function deep(n: number): Error {
	if (n === 0) {
		const o: {name: string; message: string; stack?: string} = {name: "Plain", message: "an object"};
		Error.captureStackTrace(o);
		console.log(o.stack);
		return new Error("limited");
	}
	return deep(n - 1);
}

Error.stackTraceLimit = 2;
console.log(deep(3).stack);
console.log(Error.stackTraceLimit);
