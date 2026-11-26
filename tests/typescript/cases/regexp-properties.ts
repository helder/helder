// Unicode property escapes (\p{...}, \P{...}) under the u and v flags:
// General_Category and its groups, Script and Script_Extensions, the
// binary properties, by their names and aliases
const sample: Array<string> = [];
for (let c = 0; c < 0x30000; c += 7) if (c < 0xd800 || c > 0xdfff) sample.push(String.fromCodePoint(c));
const text = sample.join("");
function count(name: string): number {
	return text.match(new RegExp(`\\p{${name}}`, "gu"))?.length ?? 0;
}
const names = ["L", "Lu", "Ll", "Lt", "Lm", "Lo", "LC", "M", "Mn", "N", "Nd", "Nl", "No", "P", "Pc", "Pd", "Ps", "Pe", "Po", "S", "Sm", "Sc", "Sk", "So",
	"Z", "Zs", "C", "Cc", "Cf", "Cn", "Co", "Letter", "punct", "gc=Lu", "General_Category=Decimal_Number",
	"Script=Latin", "sc=Grek", "sc=Cyrillic", "sc=Han", "sc=Arab", "sc=Zyyy", "sc=Zinh", "scx=Latin", "scx=Hira", "Script_Extensions=Greek", "scx=Zyyy",
	"Emoji", "Emoji_Presentation", "Emoji_Modifier", "Emoji_Modifier_Base", "Extended_Pictographic", "EComp", "Alphabetic", "White_Space",
	"ID_Start", "ID_Continue", "Uppercase", "Lowercase", "Any", "ASCII", "Assigned", "Math", "Dash", "Regional_Indicator", "Hex"];
for (const n of names) console.log(n, count(n));
console.log(/\p{L}+/u.exec("héllo wörld")?.[0], /^\P{Script=Latin}+$/u.test("αβγ"), /[\p{N}\p{P}]+/u.exec("ab12,34!cd")?.[0]);
console.log(/[^\p{L}\s]/gu[Symbol.replace]("a1 b2 ç3", ""), /\p{Lu}/ui.test("a"), /\p{Emoji_Presentation}/v.test("😀"));
console.log("👍🏽 👋 x".match(/\p{Emoji_Modifier_Base}\p{Emoji_Modifier}?|\p{Emoji_Presentation}/gu));
try {
	const name = ["No", "pe"].join("");
	new RegExp(`\\p{${name}}`, "u");
} catch (e) {
	console.log((e as Error).name, (e as Error).message);
}
// (without the u flag, \p is the letter p)
console.log(new RegExp("\\p{L}").test("p{L}"));
