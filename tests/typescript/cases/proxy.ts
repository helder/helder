// Proxy: every trap, the target's own way where a trap is missing, the
// invariants the spec checks, revocation, a proxy as a prototype and as a
// site's receiver, and Reflect beside it.
const log: string[] = [];
function note(s: string) { log.push(s); }
function flush(label: string) { console.log(label, log.join(' ')); log.length = 0; }
function fails(f: () => unknown): string {
  try { f(); return 'ok'; } catch (e) { return (e as Error).constructor.name; }
}
const key = (k: string | symbol) => typeof k === 'symbol' ? k.toString() : k;

const target: any = {a: 1, b: 2};
const traced: any = new Proxy(target, {
  get(t, k, r) { note('get:' + key(k)); return Reflect.get(t, k, r); },
  set(t, k, v, r) { note('set:' + key(k)); return Reflect.set(t, k, v, r); },
  has(t, k) { note('has:' + key(k)); return Reflect.has(t, k); },
  deleteProperty(t, k) { note('delete:' + key(k)); return Reflect.deleteProperty(t, k); },
  ownKeys(t) { note('ownKeys'); return Reflect.ownKeys(t); },
  getOwnPropertyDescriptor(t, k) { note('gopd:' + key(k)); return Reflect.getOwnPropertyDescriptor(t, k); },
  defineProperty(t, k, d) { note('define:' + key(k)); return Reflect.defineProperty(t, k, d); },
  getPrototypeOf(t) { note('getPrototypeOf'); return Reflect.getPrototypeOf(t); },
  setPrototypeOf(t, p) { note('setPrototypeOf'); return Reflect.setPrototypeOf(t, p); },
  isExtensible(t) { note('isExtensible'); return Reflect.isExtensible(t); },
  preventExtensions(t) { note('preventExtensions'); return Reflect.preventExtensions(t); },
});
console.log(traced.a, traced.missing); flush('read');
traced.c = 3; traced.a = 10; flush('write');
console.log('a' in traced, 'zz' in traced); flush('in');
console.log(delete traced.b, Object.keys(target)); flush('delete');
console.log(Object.keys(traced)); flush('keys');
console.log(JSON.stringify(traced)); flush('json');
console.log({...traced}); flush('spread');
const seen: string[] = [];
for (const k in traced) seen.push(k);
console.log(seen); flush('for-in');
Object.defineProperty(traced, 'd', {value: 4, enumerable: true, configurable: true, writable: true}); flush('defineProperty');
console.log(Object.getPrototypeOf(traced) === Object.prototype, traced instanceof Object); flush('prototype');
console.log(Object.isExtensible(traced), Object.isFrozen(traced)); flush('extensible');
console.log(Object.hasOwn(traced, 'a'), traced.hasOwnProperty('zz')); flush('hasOwn');
console.log(traced); flush('inspect');

// no traps: the target's own way
const plain: any = new Proxy({x: 1, nested: {y: 2}}, {});
plain.z = 3;
console.log(plain.x, plain.nested.y, plain.z, Object.keys(plain), JSON.stringify(plain), 'x' in plain, delete plain.x, plain.x);
// (any: a slot typed number[] holds the runtime's arrays, and a proxy of one diverges there)
const array: any = new Proxy([1, 2, 3], {});
console.log(Array.isArray(array), array.length, array.map((x: number) => x * 2), JSON.stringify(array), Object.prototype.toString.call(array));

// functions: apply and construct
function add(a: number, b: number) { return a + b; }
const adder = new Proxy(add, {apply(t, self, args) { note('apply'); return t(args[0], args[1]) * 10; }});
console.log(typeof adder, adder(1, 2), adder.call(null, 3, 4), adder.apply(null, [5, 6]), adder.name, adder.length); flush('apply');
class Point { constructor(public x: number, public y: number) {} sum() { return this.x + this.y; } }
const Made = new Proxy(Point, {construct(t, args, nt) { note('construct'); return Reflect.construct(t, [args[0] * 2, args[1] * 2], nt); }});
const made = new Made(1, 2);
console.log(made.sum(), made instanceof Point); flush('construct');
console.log(fails(() => (new Proxy({}, {}) as any)()), fails(() => new (new Proxy(() => 0, {}) as any)()));
console.log(fails(() => new (new Proxy(Point, {construct() { return 1 as any; }}))(1, 2)));

// a proxy as a prototype: reads and writes reach its traps with the receiver
const base = new Proxy({inherited: 'from target'}, {
  get(t, k, r) { note('get:' + key(k) + (r === child ? ' (child)' : '')); return Reflect.get(t, k, r); },
  set(t, k, v, r) { note('set:' + key(k)); return Reflect.set(t, k, v, r); },
  has(t, k) { note('has:' + key(k)); return Reflect.has(t, k); },
});
const child: any = Object.create(base);
child.own = 1;
console.log(child.own, child.inherited, child.nothing, 'inherited' in child, 'own' in child);
child.added = 2;
console.log(Object.keys(child)); flush('prototype proxy');

// a site seeing plain objects and proxies in turn
function readX(o: any) { return o.x; }
function writeX(o: any, v: any) { o.x = v; }
const counting = new Proxy({x: 'p'}, {get(t, k) { note('get:' + key(k)); return (t as any)[k]; }});
const objects: any[] = [{x: 1}, counting, {x: 2}, counting, {y: 0, x: 3}];
console.log(objects.map(readX)); flush('site');
for (const o of objects) writeX(o, 'w');
console.log(objects.map(o => o === counting ? (counting as any).x : o.x)); flush('site write');

// revocation
const {proxy: revocable, revoke} = Proxy.revocable({v: 1}, {});
console.log((revocable as any).v);
revoke();
try { (revocable as any).v; } catch (e) { console.log((e as Error).name + ': ' + (e as Error).message); }
console.log(fails(() => Object.keys(revocable)), fails(() => Array.isArray(revocable)));

// invariants
const frozen = Object.freeze({fixed: 1});
console.log(fails(() => (new Proxy(frozen, {get: () => 2}) as any).fixed), (new Proxy(frozen, {get: () => 1}) as any).fixed);
const sealedTarget = Object.preventExtensions({k: 1});
console.log(fails(() => 'k' in new Proxy(sealedTarget, {has: () => false})));
console.log(fails(() => Object.keys(new Proxy(sealedTarget, {ownKeys: () => []}))));
console.log(fails(() => Object.keys(new Proxy({}, {ownKeys: () => ['a', 'a']}))));
console.log(fails(() => Object.getOwnPropertyDescriptor(new Proxy(frozen, {getOwnPropertyDescriptor: () => undefined}), 'fixed')));
console.log(fails(() => Object.isExtensible(new Proxy({}, {isExtensible: () => false}))));
console.log(fails(() => Object.preventExtensions(new Proxy({}, {preventExtensions: () => true}))));
console.log(fails(() => Object.getPrototypeOf(new Proxy(sealedTarget, {getPrototypeOf: () => Array.prototype}))));
console.log(fails(() => Object.defineProperty(new Proxy({}, {defineProperty: () => false}), 'q', {value: 1})));
console.log(fails(() => { 'use strict'; (new Proxy({}, {set: () => false}) as any).q = 1; }));
console.log(fails(() => { delete (new Proxy({}, {deleteProperty: () => false}) as any).q; }));
console.log(fails(() => new Proxy(1 as any, {})), fails(() => (Proxy as any)({}, {})));

// Reflect
const r: any = {a: 1};
Object.defineProperty(r, 'ro', {value: 1, writable: false});
console.log(Reflect.set(r, 'ro', 2), Reflect.set(r, 'a', 5), r.a, Reflect.deleteProperty(Object.freeze({z: 1}), 'z'));
console.log(Reflect.defineProperty(Object.freeze({}), 'n', {value: 1}), Reflect.setPrototypeOf(Object.preventExtensions({}), Array.prototype));
console.log(Reflect.has(r, 'a'), Reflect.ownKeys({b: 1, [Symbol.iterator]: 0}), Reflect.getPrototypeOf([]) === Array.prototype);
console.log(Reflect.apply(Math.max, null, [1, 3, 2]), Reflect.construct(Date, [0]) instanceof Date, Reflect.isExtensible({}));
const receiver: any = {};
Reflect.set({set v(x: number) { (this as any).got = x; }}, 'v', 7, receiver);
Reflect.set({}, 'w', 8, receiver);
console.log(receiver, Reflect.get({get g() { return this; }}, 'g', receiver) === receiver);
console.log(fails(() => Reflect.get(1 as any, 'x')), fails(() => Reflect.apply(1 as any, null, [])), fails(() => Reflect.construct((() => 0) as any, [])));

// setPrototypeOf and __proto__, cached sites invalidated
const protoA = {who() { return 'A'; }}, protoB = {who() { return 'B'; }};
const switching: any = Object.create(protoA);
function who(o: any) { return o.who(); }
console.log(who(switching), who(switching));
Object.setPrototypeOf(switching, protoB);
console.log(who(switching));
switching.__proto__ = protoA;
console.log(who(switching), switching.__proto__ === protoA);
console.log(fails(() => Object.setPrototypeOf(protoA, switching)), fails(() => Object.setPrototypeOf(Object.preventExtensions({}), protoA)));
