// Rejected at its own line, after comments and non-ASCII text.
const label = "☃ 😀";

/* expect: position.ts:5: TSHX001 */
const r = new WeakRef({});
