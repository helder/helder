const values = [10, 20];
const descriptor = Object.getOwnPropertyDescriptor(values, "0")!;
console.log(descriptor.value, descriptor.writable, descriptor.enumerable, descriptor.configurable);
Object.preventExtensions(values);
console.log(Object.getOwnPropertyDescriptor(values, "1")!.writable);
