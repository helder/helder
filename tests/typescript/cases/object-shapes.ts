// Shapes and sites (js/Shapes.hx, js/Sites.hx): objects of the same keys
// share a shape, a site records what it found by shape, and what it found
// on a prototype stops holding when the prototype changes.
function readName(o: any): any { return o.name; }
function writeName(o: any, v: any) { o.name = v; }
function callGreet(o: any): any { return o.greet(); }

// one site, many shapes (more than a site's record keeps)
const many: any[] = [{name: 'a'}, {x: 1, name: 'b'}, {y: 2, x: 1, name: 'c'}, {name: 'd', z: 0}, {w: 1, name: 'e'}, {q: 1, w: 1, name: 'f'}];
for (let r = 0; r < 3; r++) console.log(many.map(readName).join(''));
console.log(readName({}), readName([]), readName(() => 0), readName('str'), readName(1), readName(new Map()));

// writes: in place, new properties, a frozen object's, a setter's
const w: any = {name: 'x'};
for (const v of ['p', 'q']) writeName(w, v);
console.log(w.name, Object.keys(w));
const fresh: any[] = [{}, {}, {a: 1}];
for (const f of fresh) writeName(f, 'n');
console.log(JSON.stringify(fresh));
const frozen = Object.freeze({name: 'ice'});
try { writeName(frozen, 'water'); } catch (e) { console.log((e as Error).name); }
console.log(frozen.name);
const sealed: any = Object.preventExtensions({});
writeName({}, 'warm');
try { writeName(sealed, 'cold'); } catch (e) { console.log((e as Error).name); }
console.log(sealed.name);
const setterProto = {set name(v: any) { console.log('setter', v); }};
const viaSetter = Object.create(setterProto);
writeName(viaSetter, 'set');
console.log(Object.keys(viaSetter));

// prototypes: a method replaced, shadowed, deleted, the prototype changed
// (a class expression: no typed layout, its prototype not locked)
const Greeter = class { greet() { return 'hello'; } };
const g: any = new Greeter();
const proto: any = Greeter.prototype;
console.log(callGreet(g), callGreet(g));
proto.greet = () => 'hi';
console.log(callGreet(g));
g.greet = () => 'own';
console.log(callGreet(g));
delete g.greet;
console.log(callGreet(g));
const other = {greet() { return 'other'; }};
Object.setPrototypeOf(g, other);
console.log(callGreet(g));
const middle: any = Object.create(other);
const bottom: any = Object.create(middle);
console.log(callGreet(bottom));
middle.greet = () => 'middle';
console.log(callGreet(bottom));
delete middle.greet;
console.log(callGreet(bottom));
const absent: any = {};
console.log(readName(absent));
(Object.prototype as any).name = 'from Object.prototype';
console.log(readName(absent), readName({}));
delete (Object.prototype as any).name;
console.log(readName(absent));

// accessors, own and inherited
const own: any = {};
Object.defineProperty(own, 'name', {get() { return 'got'; }, enumerable: true, configurable: true});
console.log(readName(own), readName(own));
Object.defineProperty(own, 'name', {value: 'data', writable: true});
console.log(readName(own));
class Named { get name() { return 'named'; } }
console.log(readName(new Named()), readName(new Named()));

// deletes, order, many keys (a dictionary)
const d: any = {a: 1, b: 2, c: 3};
delete d.b;
d.b = 4;
delete d.c;
console.log(Object.keys(d), JSON.stringify(d));
const big: any = {};
for (let i = 0; i < 300; i++) big['k' + i] = i;
for (let i = 0; i < 300; i += 3) delete big['k' + i];
console.log(Object.keys(big).length, Object.keys(big).slice(0, 5), big.k1, big.k3);
const literal = {b: 1, 2: 'two', a: 3, 1: 'one'};
console.log(Object.keys(literal), JSON.stringify(literal));

// spread: a copy, independent of its source
const src = {id: 1, name: 'src', tags: ['t']};
const copy = {...src, label: 'L'};
src.name = 'changed';
console.log(copy.name, copy.label, Object.keys(copy), copy.tags === src.tags);
const withAccessor = {...{get v() { return 'computed'; }}};
console.log(Object.getOwnPropertyDescriptor(withAccessor, 'v'));
const hidden = Object.defineProperty({shown: 1}, 'hidden', {value: 2, enumerable: false});
console.log({...hidden});

// typed classes' fields and built-ins' own properties by name
class Point { constructor(public x: number, public y: number) {} }
const pts: any[] = [new Point(1, 2), {x: 3, y: 4}, new Point(5, 6)];
console.log(pts.map((p: any) => p.x + p.y));
const things: any[] = [[1, 2, 3], 'abcd', function named() {}, new Uint8Array(2)];
console.log(things.map((t: any) => t.length), things.map((t: any) => typeof t.name));
