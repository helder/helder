// JSON.parse's objects given their shapes at once (keys read against a
// recent object's), numbers without a string, number arrays; stringify in
// one builder reading plain arrays' elements and plain and typed objects'
// properties directly; and where each takes the general way.
const rows = JSON.parse('[{"id":1,"name":"a","tags":[1,2]},{"id":2,"name":"b","tags":[]},{"name":"c","id":3},{"id":4,"name":"d","extra":true},{"id":5}]');
console.log(rows, rows.map((r: any) => Object.keys(r).join()), rows[0].tags.concat(['x']), Array.isArray(rows[1].tags));
rows[0].tags.push('s');
rows[1].id = 'changed';
delete rows[0].name;
console.log(JSON.stringify(rows), Object.keys(rows[0]));
console.log(JSON.parse('{"a":1,"a":2,"b":3}'), JSON.parse('{"__proto__":1,"x":2}').__proto__, Object.keys(JSON.parse('{"b":1,"2":2,"1":3,"a":4}')), JSON.parse('{"a\\"b":1,"a\\u0041":2,"aA":3}'));
console.log(JSON.parse('[0,-0,1.5,-2.25,0.1,123456789012345,1234567890123456789,1e3,2E-2,0.000001,9007199254740993,1.7976931348623157e308,5e-324]'), 1 / JSON.parse('-0'), JSON.parse('[1,"2",3]'), JSON.parse('[[1,2],[3,"x"],[]]'));
console.log(JSON.parse('"plain"'), JSON.parse('"tab\\tquote\\"slash\\/u\\u00e9\\ud83d\\ude00"'), JSON.parse('" é 😀 "'), JSON.parse('{"k":"v","k2":"\\n"}'));
for (const bad of ['[1,]', '{"a":1,}', '01', '1.', '-', '"a\\x"', '"\u0001"', '{"a" 1}', '[1 2]', '"abc']) {
  try { JSON.parse(bad); console.log('parsed', bad); } catch (e) { console.log((e as Error).name); }
}

// stringify: indentation, replacers, toJSON, holes, wrappers, what is not JSON
const value: any = {s: 'a"b\\c\n\u0001 ', n: [1, -0, 1.5, NaN, Infinity], b: [true, false, null], u: undefined, f() {}, sym: Symbol('x'), nested: {deep: [{x: 1}, []], empty: {}}};
console.log(JSON.stringify(value), JSON.stringify(value, null, 2), JSON.stringify(value, null, '--'));
console.log(JSON.stringify(value, (k, v) => typeof v === 'number' ? v * 2 : v), JSON.stringify(value, ['s', 'nested', 'deep', 'x']), JSON.stringify([undefined, () => 0, Symbol('s')]));
const holes: any[] = [1, , 3];
(Array.prototype as any)[1] = 'proto';
const own: any = [1, 2];
own.extra = 'not written';
console.log(JSON.stringify(holes), JSON.stringify(own), JSON.stringify(new Uint8Array([1, 2])), JSON.stringify(new Map([[1, 2]])), JSON.stringify([new Number(3), new String('s'), new Boolean(false)]));
delete (Array.prototype as any)[1];
console.log(JSON.stringify({date: new Date(0), toJSON: undefined}), JSON.stringify({a: {toJSON(k: string) { return 'key ' + k; }}, list: [{toJSON(k: string) { return k; }}]}));
console.log(JSON.stringify({'2': 'b', '1': 'a', z: 1, [Symbol.iterator]: 0}), JSON.stringify({get g() { return 'got'; }, h: 1}), JSON.stringify('\ud800 \udc00 😀'), JSON.stringify({'\ud800': 1}));
const later: any = {first: {toJSON() { delete later.second; later.third = 3; return 1; }}, second: 2};
console.log(JSON.stringify(later));
const circular: any = {a: [1]};
circular.a.push(circular);
try { JSON.stringify(circular); } catch (e) { console.log((e as Error).name); }

// typed objects: an object type's layout, a class's fields, then given more
type Point = {x: number, y: number, label: string}
const points: Point[] = [{x: 1, y: 2, label: 'p'}, {x: 3, y: 4, label: 'q'}];
class Item { id = 7; name = 'item'; price = 2.5; tags: string[] = ['t']; }
const item = new Item();
console.log(JSON.stringify(points), JSON.stringify(item), JSON.stringify([item, item], null, 1));
(points[0] as any).z = 9;
(item as any).more = true;
console.log(JSON.stringify(points), JSON.stringify(item), JSON.stringify(JSON.parse(JSON.stringify({points, item}))));

// toJSON is an object's alone: a string's or a number's on their prototypes is not called
(String.prototype as any).toJSON = () => 'string toJSON';
(Number.prototype as any).toJSON = () => 'number toJSON';
console.log(JSON.stringify(['s', 1, {n: 2}]), JSON.stringify(new String('w')), JSON.stringify(Object(3)));
delete (String.prototype as any).toJSON;
delete (Number.prototype as any).toJSON;
