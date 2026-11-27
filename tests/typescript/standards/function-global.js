// The global object as libraries find it (lodash's root): no node `global`
// or browser `self`, then Function("return this")(); other code from a
// string stays an EvalError
function check(ok, what) {
	if (!ok) throw new Error(what);
}
const root = (typeof global == "object" && global) || (typeof self == "object" && self) || Function("return this")();
check(root === globalThis && root.Math === Math, "Function('return this')()");
check(new Function("return this")() === globalThis, "new Function('return this')()");
let threw = false;
try {
	Function("return 1");
} catch (e) {
	threw = e instanceof EvalError;
}
check(threw, "other code from a string: an EvalError");
console.log("ok");
