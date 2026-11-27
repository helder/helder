const values = [10, 20, 30];
Object.defineProperties(values, {
  0: { value: 11, writable: false, configurable: false },
  1: { get: () => 21, enumerable: false },
  4: { value: 40, configurable: true },
});
console.log(values.length, values[0], values[1], values[4], Object.keys(values).join(","));
console.log(Object.getOwnPropertyNames(values).join(","), values.map(x => x).join(","));
Object.defineProperty(values, "0", { value: 11 });
console.log(Reflect.defineProperty(values, "0", { writable: true }));
try {
  Object.defineProperty(values, "0", { enumerable: false });
} catch (error) {
  console.log(error instanceof TypeError);
}
try {
  Object.defineProperty(values, "length", { value: 0, writable: false });
} catch (error) {
  console.log(error instanceof TypeError, values.length);
}
console.log(Reflect.defineProperty(values, "1", { value: 50 }));
