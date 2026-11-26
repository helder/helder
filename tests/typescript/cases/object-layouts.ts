// Object types' layouts (lower/Reps.hx's ObjectLayout): literals of plain
// properties made with their properties in typed slots, read and written
// through a guard on the layout; a value a slot does not take, a delete, an
// accessor or an attribute make that object an ordinary one, its
// properties in their order; structural typing lets any object arrive.
type Row = {id: number, name: string, score: number, flag: boolean, tags: string[]}
function row(i: number): Row { return {id: i, name: 'r' + i, score: i * 1.5, flag: i % 2 === 0, tags: ['t' + i]}; }
function total(rows: Row[]): number {
  let s = 0;
  for (const r of rows) s += r.score + (r.flag ? 1 : 0) + r.tags.length;
  return s;
}
const rows = [row(1), row(2), row(3)];
console.log(total(rows), rows.map(r => r.name).join(','), JSON.stringify(rows[0]), Object.keys(rows[1]));

// writes in place, and ones a slot does not take (through any): that row is ordinary from then on
rows[0].score = 10;
rows[0].name = 'renamed';
(rows[1] as any).score = 'not a number';
(rows[2] as any).flag = null;
console.log(total([rows[0], rows[2]]), rows[1].score, JSON.stringify(rows[1]), Object.keys(rows[1]), rows[2].flag);
rows[1].score = 4;
console.log(rows[1].score + 1, typeof rows[1].score);

// other objects of the type: a plain one, one with more, a class's, one parsed
class RowClass { id = 7; name = 'c'; score = 2; flag = true; tags = ['x']; }
const others: Row[] = [JSON.parse('{"id":1,"name":"j","score":0.5,"flag":false,"tags":[]}'), new RowClass(), Object.assign({extra: 1}, row(4)), {...row(5), score: 100}];
console.log(total(others), others.map(r => r.score));

// deletes, accessors, attributes, extra properties, in order
const d = row(6) as any;
d.extra = 'e';
delete d.name;
console.log(Object.keys(d), JSON.stringify(d), d.name, d.extra);
const a = row(7) as any;
Object.defineProperty(a, 'score', {get() { return 42; }, enumerable: true});
console.log(a.score, Object.keys(a), total([a]));
const f = Object.freeze(row(8));
try { (f as any).score = 1; } catch (e) { console.log((e as Error).name); }
console.log(f.score, Object.isFrozen(f));
const s = Object.seal(row(9));
s.score = 3;
console.log(s.score, Object.isSealed(s), Object.getOwnPropertyDescriptor(s, 'score'));

// optional properties: a literal without one, given it later
type Opt = {x: number, y?: number, label?: string}
const opts: Opt[] = [{x: 1}, {x: 2, y: 3}, {x: 4, label: 'l'}];
opts[0].y = 5;
console.log(opts.map(o => (o.y ?? 0) + o.x), opts.map(o => 'y' in o), JSON.stringify(opts));
delete opts[1].y;
console.log(JSON.stringify(opts[1]), Object.keys(opts[1]));

// spreads: of an exact instance, of one with more, of an ordinary one, overriding, adding
const base = row(10);
const plus = {...base, label: base.name + '!'};
const more = Object.assign(row(11), {more: true});
const fromMore = {...more, label: 'm'};
const fromPlain = {...({id: 0, name: 'p', score: 1, flag: false, tags: []} as Row), label: 'p'};
const override = {...base, score: -1};
base.score = 0;
console.log(plus.label, plus.score, Object.keys(plus), Object.keys(fromMore), fromPlain.label, override.score, Object.keys(override));
const nested = {...plus, extra: {...plus}};
console.log(JSON.stringify(nested).length, nested.extra.label);

// numbers read unboxed into arithmetic, relations, typed slots
let acc = 0;
for (let i = 0; i < 1000; i++) {
  const r = row(i);
  if (r.score > 100 && r.id % 3 === 0) acc += r.score * 2 - r.id;
}
const one: number = row(3).score;
console.log(acc, one);
const weird = [row(1), {id: 'x' as any as number, name: 'w', score: 'y' as any as number, flag: true, tags: []}];
console.log(weird.map(r => r.score * 2), weird.map(r => r.score > 1), weird.map(r => r.score + 1), weird.map(r => r.score > weird[0].score));
