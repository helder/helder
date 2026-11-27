// JavaScript's JSDoc types are unchecked (checkJs off): a value they do not
// describe is the runtime's, as node runs it (lodash's stackGet: a key
// `{string}` given objects)
function check(ok, what) {
	if (!ok) throw new Error(what);
}
/** @param {string} key @returns {number} */
function size(key) {
	return typeof key === "string" ? key.length : key;
}
/** @type {number} */
let count = 0;
check(size("abc") === 3, "a string");
const o = {};
check(size(o) === o, "an object where a string is declared");
check(size([1, 2]).length === 2, "an array");
count = "many";
check(count === "many", "a string where a number is declared");
console.log("ok");
