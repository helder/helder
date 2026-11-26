// Unary + and - make numbers of typed booleans and strings (date-fns:
// `difference - +isLastMonthNotFull`)
let full = Math.random() < 2;
const text = String(42);
console.log(5 - +full, -full, +text, -text, +!full);
full = false;
console.log(+full, -full, 1 + +full, +"0x10", -"", +" 2 ");
