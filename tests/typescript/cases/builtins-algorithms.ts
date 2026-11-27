// Built-ins' algorithms: sort as a stable merge of runs (in place for a
// plain array, primitives' text made once), localeCompare's ASCII way, Map
// and Set keys that are 32-bit integers looked up as integers.
function lcg(seed: number) { return () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648; }
const random = lcg(7);
const people = Array.from({length: 300}, (_, i) => ({name: 'p' + i, age: Math.floor(random() * 20)}));
const byAge = [...people].sort((a, b) => a.age - b.age);
console.log(byAge.every((p, i) => i === 0 || byAge[i - 1].age < p.age || byAge[i - 1].age === p.age && Number(byAge[i - 1].name.slice(1)) < Number(p.name.slice(1))));
const runs = [...Array(100).keys(), ...Array.from({length: 100}, (_, i) => 200 - i), ...Array.from({length: 50}, () => 7)];
console.log(runs.slice().sort((a, b) => a - b).join() === runs.slice().sort((a, b) => a - b).join(), runs.slice().sort((a, b) => b - a).slice(0, 5), runs.slice().sort().slice(0, 8));
console.log([10, 9, 1, 100, -1, 0.5, -0, NaN].sort(), [3, undefined, 1, , 2].sort(), ['b', undefined, 'a', , 'c'].sort().length, [true, false, null, 'null', 'true'].sort());
const objects = [{toString() { return 'b'; }}, {toString() { return 'a'; }}];
console.log(objects.sort().map(String), [5, 1, 4].sort(() => NaN), [5, 1, 4].sort((a, b) => (a > b) as any), [2, 1].sort(undefined));
const own: any = [3, 1, 2];
own.extra = 'kept';
const holes: any[] = [3, , 1];
const like: any = {length: 3, 0: 'c', 1: 'a', 2: 'b'};
console.log(own.sort(), own.extra, holes.sort(), holes.length, 1 in holes, Array.prototype.sort.call(like), [3, 1, 2].toSorted(), [, 1].toSorted());
const changing = [5, 4, 3, 2, 1];
console.log(changing.sort((a, b) => (changing.length < 8 && changing.push(0), a - b)), changing.length);
try { (Object.freeze([2, 1]) as number[]).sort(); } catch (e) { console.log((e as Error).name); }
try { [2, 1].sort('x' as any); } catch (e) { console.log((e as Error).name); }
let calls = 0;
[...Array(64).keys()].sort((a, b) => (calls++, a - b));
console.log(calls < 64 * 6, new Float64Array([3, -1, 2]).sort(), ['é', 'e', 'z', 'E', 'a'].sort());

// localeCompare: equal, case, accents, prefixes, digits and punctuation
const words = ['b', 'a', 'B', 'A', 'ab', 'Ab', 'a-b', 'a b', 'a1', 'a10', 'a2', 'é', 'e', 'E', 'z', '', 'zz', '_x', '~'];
console.log(words.slice().sort((x, y) => x.localeCompare(y)), 'abc'.localeCompare('abc'), 'a'.localeCompare('b'), 'b'.localeCompare('a'), 'a'.localeCompare('A'), 'résumé'.localeCompare('resume'));

// Map and Set keys: integers, -0, fractions, NaN, beyond 32 bits, strings that look like numbers
const m = new Map<any, string>();
for (const k of [1, -1, 0, -0, 2147483647, 2147483648, -2147483648, -2147483649, 2 ** 53, 1.5, NaN, '1', true]) m.set(k, typeof k + ':' + String(k));
console.log([...m.keys()], m.size, m.get(-0), m.get(0), m.get(1), m.get('1'), m.get(1.5), m.get(NaN), m.has(2147483648), m.has(2 ** 31 - 1), m.get(-2147483649));
m.delete(0);
m.delete(1);
m.set(1, 'again');
m.set(0, 'zero');
console.log([...m.entries()].slice(0, 3), [...m.entries()].slice(-2), m.has(-0));
const s = new Set<any>([3, 3.0, -0, 0, 1e9, 1e10, '3']);
console.log([...s], s.has(3), s.has(1e10), s.has(10000000000), s.delete(-0), [...s]);
m.clear();
console.log(m.size, m.get(2147483647), m.has(NaN));
