// helder/test's properties from TypeScript (natively and as wasm32-wasi):
// generators composed, a property and a stateful one that hold, a case
// rejected by assume.
import {test, equals, assert, property, stateful, assume, gen, int, float, bool, pick, oneOf, array, string, constant, recursive} from "helder/test";

type Tree = number | Array<Tree>;

test("sorting: ordered, the same items", () => property(array(int(-50, 50)), xs => {
	const sorted = [...xs].sort((a, b) => a - b);
	equals(sorted.length, xs.length);
	for (let i = 1; i < sorted.length; i++) assert(sorted[i - 1] <= sorted[i]);
}));

test("generators: in their ranges", () => property(gen(c => ({
	n: c.draw(int(3, 7)),
	f: c.draw(float(0, 1)),
	b: c.draw(bool()),
	p: c.draw(pick(["a", "b"])),
	o: c.draw(oneOf([constant(1), int(10, 12)])),
	s: c.draw(string(pick(["x", "y"]), 1, 4)),
	t: c.draw(recursive<Tree>(int(0, 9), t => array(t, 0, 3), 2)),
	even: c.draw(int(0, 100).filter(x => x % 2 == 0).map(x => x / 2))
})), v => {
	assert(v.n >= 3 && v.n <= 7);
	assert(v.f >= 0 && v.f <= 1);
	assert(v.p === "a" || v.p === "b");
	assert(v.o === 1 || (v.o >= 10 && v.o <= 12));
	assert(v.s.length >= 1 && v.s.length <= 4 && /^[xy]+$/.test(v.s));
	assert(Number.isInteger(v.even) && v.even <= 50);
}));

test("assume: rejected cases left out", () => property(int(0, 20), x => {
	assume(x % 3 == 0);
	equals(x % 3, 0);
}));

test("stateful: a counter and its model", () => stateful({
	setup: () => ({count: 0, model: 0}),
	steps: [
		{name: "add", run: (s, c) => {
			const n = c.draw(int(1, 5));
			s.count += n;
			s.model += n;
		}},
		{name: "reset", run: s => {
			s.count = 0;
			s.model = 0;
		}, when: s => s.count > 0}
	],
	check: s => equals(s.count, s.model)
}));
