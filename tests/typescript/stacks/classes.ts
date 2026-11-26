// methods, getters, setters, constructors, static methods and an object
// literal's methods
function show(f: () => unknown) {
	try {
		f();
	} catch (e) {
		console.log((e as Error).stack);
	}
}

class Shape {
	constructor(readonly sides: number) {
		if (sides < 3) throw new RangeError("too few sides: " + sides);
	}

	get name(): string {
		throw new Error("no name for " + this.sides);
	}

	describe(prefix: string): string {
		const text = prefix + " " + this.name;
		return text.toUpperCase();
	}

	static of(sides: number): Shape {
		const s = new Shape(sides);
		return s;
	}
}

const tools = {
	parse(text: string): number {
		const n = Number(text);
		if (Number.isNaN(n)) throw new SyntaxError("not a number: " + text);
		return n;
	},
	twice: (text: string) => tools.parse(text) * 2
};

show(() => new Shape(4).describe("a"));
show(() => Shape.of(2));
show(() => tools.twice("x"));
