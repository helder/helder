// A real package: valibot 1.1.0 (MIT, its LICENSE.md beside it), its
// dist/index.js as published (its emoji pattern: \p{...} escapes, at
// module init); its types: a short index.d.ts of what this uses
import * as v from "valibot";

const User = v.object({
	name: v.pipe(v.string(), v.trim(), v.minLength(2), v.maxLength(20)),
	age: v.pipe(v.number(), v.integer(), v.minValue(0)),
	email: v.pipe(v.string(), v.email()),
	mood: v.optional(v.pipe(v.string(), v.emoji())),
	role: v.picklist(["admin", "user"]),
	tags: v.array(v.string())
});
type User = v.InferOutput<typeof User>;

const ok = v.safeParse(User, {name: "  Ada  ", age: 36, email: "ada@example.com", mood: "🙂", role: "admin", tags: ["math"]});
console.log(ok.success, ok.success ? JSON.stringify(ok.output) : "");
const bad = v.safeParse(User, {name: "A", age: -1.5, email: "nope", mood: "x", role: "guest", tags: [1]});
console.log(bad.success);
if (!bad.success) for (const issue of bad.issues) console.log(issue.type, issue.path?.map(p => p.key).join("."), issue.message);
try {
	v.parse(User, null);
} catch (e) {
	console.log(e instanceof v.ValiError, (e as v.ValiError).issues[0].message);
}
const u: User = v.parse(User, {name: "Grace", age: 85, email: "grace@navy.mil", role: "user", tags: []});
console.log(u.name, v.is(v.array(v.number()), [1, 2, 3]), v.is(v.boolean(), "no"));
