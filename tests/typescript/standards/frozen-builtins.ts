// The built-ins' members are frozen (src/helder/typescript/README.md, "Strict"):
// written, redefined or deleted they throw a TypeError, their descriptors say
// so, and an object inheriting one may still have its own (node differs: there
// they are writable).
function throws(f: () => unknown, what: string) {
  try { f(); } catch (e) { if (e instanceof TypeError) return; throw e; }
  throw new Error(what + " did not throw");
}
const proto: any = Array.prototype, math: any = Math, json: any = JSON, map: any = Map.prototype;
throws(() => { proto.map = () => 0; }, "Array.prototype.map written");
throws(() => { math.max = () => 0; }, "Math.max written");
throws(() => { json.stringify = () => ""; }, "JSON.stringify written");
throws(() => { delete map.get; }, "Map.prototype.get deleted");
throws(() => Object.defineProperty(String.prototype, "trim", {value: () => ""}), "String.prototype.trim redefined");
const d = Object.getOwnPropertyDescriptor(Array.prototype, "filter")!;
if (d.writable || d.configurable || d.enumerable) throw new Error("Array.prototype.filter's descriptor");
if (!Reflect.set(proto, "added", 1) || proto.added !== 1) throw new Error("a new member is not frozen");
delete proto.added;
// (an object's own member over an inherited frozen one)
const own: any = [1, 2, 3];
own.map = () => "own";
if (own.map() !== "own") throw new Error("an array's own map");
const o: any = {};
o.toString = () => "mine";
if (String(o) !== "mine") throw new Error("an object's own toString");
if ([1, 2, 3].map(x => x * 2).join() !== "2,4,6") throw new Error("the built-in map");
console.log("frozen");
