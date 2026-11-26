/* expect: regexp-unsupported.ts:3: TSHX001: Invalid regular expression */
// (a set operation of the v flag: tsgo accepts it, helder's RegExp does not yet)
const r = /[\p{L}--[a-z]]/v;
console.log(r.test("é"));
