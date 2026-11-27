const source = [3, 4];
const target = Object.preventExtensions({});
Object.defineProperty(source, "constructor", {
  value: { [Symbol.species]: function () { return target; } },
  configurable: true,
});

for (const operation of [
  () => source.filter(x => x > 0),
  () => source.map(x => x * 2),
  () => source.flatMap(x => [x]),
  () => source.slice(),
  () => source.splice(0, 1),
  () => source.concat([]),
  () => source.flat(),
]) {
  try {
    operation();
    console.log("accepted");
  } catch (error) {
    console.log(error instanceof TypeError);
  }
}
console.log((source.filter(() => false) as unknown) === target, source.length);

const result = Object.preventExtensions([0, 0]);
Object.defineProperty(source, "constructor", {
  value: { [Symbol.species]: function () { return result; } },
});
console.log(source.map(x => x * 2) === result, result.join(","));
