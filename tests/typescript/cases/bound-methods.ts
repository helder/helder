// An own property over a typed class's method (zod's constructor:
// `this.parse = this.parse.bind(this)`): ordinary JavaScript, the instance's
// own value is what a call runs; methods no one writes stay direct
class Counter {
	count = 0;
	step: number;
	constructor(step: number) {
		this.step = step;
		this.add = this.add.bind(this);
	}
	add(n: number): number {
		return (this.count += n * this.step);
	}
	twice(): number {
		return this.add(1) + this.add(1);
	}
}
class Loud extends Counter {
	override add(n: number): number {
		return super.add(n) * 10;
	}
}
const c = new Counter(2), {add} = c;
console.log(add(1), add(2), c.twice(), c.count, Object.hasOwn(c, "add"), Object.hasOwn(c, "twice"));
const l = new Loud(1);
console.log(l.add(1), l.twice(), Object.keys(l));
// (another instance's own function, set from outside)
const d = new Counter(1);
d.add = n => -n;
console.log(d.add(5), d.twice(), new Counter(3).add(1));
