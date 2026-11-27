// An array's element into a typed slot (a declaration, an argument, a
// return, for-of's binding): the slot's class tested right after the load,
// the runtime's read where that fails; counters that never go below 0 read
// with their upper bound alone tested.
class Vec { constructor(public x: number, public y: number) {} len() { return Math.hypot(this.x, this.y); } }
class Tagged extends Vec { tag = 't'; }
const vs: Vec[] = [new Vec(3, 4), new Tagged(6, 8), new Vec(0, 1)];
function first(xs: Vec[]): Vec { return xs[0]; }
function lenOf(v: Vec): number { return v.len(); }
let total = 0;
for (let i = 0; i < vs.length; i++) {
  const v = vs[i];
  total += v.len() + lenOf(vs[i]);
  for (let j = i + 1; j < vs.length; j++) {
    const w: Vec = vs[j];
    total += v.x * w.y;
  }
}
console.log(total, first(vs).x, vs[1] instanceof Tagged, (vs[1] as Tagged).tag);

// the array changing under the loop: grown, shrunk, an element replaced, an index on the prototype
const grow: Vec[] = [new Vec(1, 1)];
for (let i = 0; i < 4; i++) {
  const v = grow[i];
  grow.push(new Vec(v.x + 1, v.y * 2));
}
const shrink: Vec[] = [new Vec(1, 0), new Vec(2, 0), new Vec(3, 0)];
const seen: number[] = [];
for (let i = 0; i < 2; i++) {
  const v = shrink[i];
  seen.push(v.x);
  shrink.pop();
  shrink.push(new Vec(9, 9));
}
console.log(grow.map(v => v.x + ':' + v.y).join(), seen, shrink.map(v => v.x));
const sparse: Vec[] = [new Vec(1, 2), new Vec(5, 6)];
delete (sparse as any)[1];
(Array.prototype as any)[1] = new Vec(7, 7);
for (let i = 0; i < 2; i++) { const v = sparse[i]; console.log(v.x, v.y); }
delete (Array.prototype as any)[1];

// for-of over instances, over arrays of arrays, counting down, a picked index
const rows: number[][] = [[1, 2], [3], []];
let sum = 0;
for (const v of vs) sum += v.x;
for (const r of rows) sum += r.length;
for (let i = rows.length - 1; i >= 0; i--) { const r: number[] = rows[i]; sum += r.length * 10; }
const nums = [10, 20, 30];
for (let i = 2; i >= 0; i--) sum += nums[i];
for (let i = 0; i < 3; i++) sum += nums[i] + (i > 0 ? nums[i - 1] : 0);
const pick = (k: number): Vec => vs[k];
console.log(sum, pick(2).y, pick(1.0).x, [vs[0]].map(v => v.len()));
const ok = (b: boolean) => b ? vs[0] : vs[2];
console.log(ok(true).x, ok(false).y);
