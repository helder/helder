// Calls and built-ins (stage 3): functions called at their arity, iteration
// methods with an inline arrow as loops, built-ins' methods called directly
// on receivers of known types; each as the method does it, for the arrays
// and receivers that take the generic way too.
const nums = [5, 1, 4, 2, 3];
const words = ['pear', 'fig', 'apple', 'kiwi'];
console.log(nums.filter(x => x > 2), nums.map(x => x * 10), nums.some(x => x > 4), nums.every(x => x > 0), nums.find(x => x % 2 === 0), nums.findIndex(x => x === 4));
console.log(words.filter((w, i) => i % 2 === 0), words.map((w, i, a) => w + i + a.length), words.reduce((acc, w) => acc + w.length, 0), words.find(w => w === 'none'), words.findIndex(w => w === 'none'));
let seen = 0;
nums.forEach(x => { seen += x; });
console.log(seen);

// holes, an index on the prototype, elements changed while iterating
const holes: any[] = [1, , 3, , 5];
console.log(holes.map(x => x * 2), holes.filter(x => true), holes.some(x => x === undefined), holes.every(x => x !== undefined), holes.findIndex(x => x === undefined));
(Array.prototype as any)[1] = 'proto';
console.log(holes.map(x => x), [0, , 2].filter(x => typeof x === 'string'));
delete (Array.prototype as any)[1];
const grow = [1, 2, 3];
console.log(grow.map(x => (grow.push(x), x)), grow.length);
const shrink = [1, 2, 3, 4];
console.log(shrink.filter(x => (shrink.length = 2, true)));
const mixed: number[] = [1, 2, 3];
console.log(mixed.map((x, i) => (i === 0 ? (mixed as any[]).push('s') : 0, x)), mixed);

// nesting, captures, this
const pairs = nums.filter(x => words.some(w => w.length === x));
const makers = nums.map(x => () => x * 2);
class Scaler { factor = 3; apply(xs: number[]) { return xs.map(x => x * this.factor); } }
console.log(pairs, makers.map(f => f()), new Scaler().apply([1, 2]));

// receivers that take the generic way: a subclass, an own method, not an array
class Stack<T> extends Array<T> {}
const stack = new Stack<number>();
stack.push(1, 2, 3);
const own: any = [1, 2, 3];
own.map = () => 'own map';
const arrayLike = {length: 2, 0: 'a', 1: 'b'};
console.log([...stack.map(x => x + 1)], own.map((x: number) => x), Array.prototype.map.call(arrayLike, (x: any) => x + '!'));

// calls at their arity: fewer arguments, more, rest, arguments
function three(a?: any, b?: any, c?: any) { return [a, b, c]; }
const f: any = three;
const rest = (...xs: any[]) => xs.length;
function args() { return arguments.length; }
const g: any = args;
console.log(f(), f(1), f(1, 2, 3, 4), rest(), rest(1, 2, 3, 4, 5), g(1, 2), [3, 1, 2].sort((a, b) => a - b), [[1, 2], [3]].map(xs => xs.length));
const o = {m(a: number, b: number) { return a + b; }, n() { return this === o; }};
console.log(o.m(1, 2), o.n(), [1, 2, 3].map(Math.sqrt), ['1', '2', '3'].map(Number), ['10', '10', '10'].map(parseInt));

// direct calls: Map, Set, includes, indexOf
const m = new Map<any, number>();
m.set(-0, 1).set(NaN, 2).set('k', 3);
console.log(m.get(0), m.get(NaN), m.has('k'), m.has('x'), m.get('x'), m.size);
const s = new Set<any>([1, 'a']);
s.add(NaN).add(NaN);
console.log(s.has(NaN), s.has(1), s.has('1'), s.size);
console.log([1, NaN, 3].includes(NaN), [1, NaN].indexOf(NaN), [1, , 3].includes(undefined), [1, , 3].indexOf(undefined), ['a', 'b'].indexOf('b'), [0].includes(-0));
class MyMap<K, V> extends Map<K, V> { get(k: K) { return 'sub' as any; } }
const mm = new MyMap<string, number>();
const tagged = new Map<string, number>();
(tagged as any).get = () => 'own';
console.log(mm.get('a'), tagged.get('a'));
