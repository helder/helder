// A built-in's member written where the compiler sees it: rejected.
/* expect: frozen-member.ts:3: TSHX001 */
Array.prototype.includes = function () { return false; };
