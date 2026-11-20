import { readFileSync, writeFileSync } from 'node:fs';

// node src/helder/os/locale/gen-plurals.mjs plurals.json parentLocales.json
// Both inputs are from cldr-json/cldr-json/cldr-core/supplemental at 48.2.0.
const data = JSON.parse(readFileSync(process.argv[2])).supplemental['plurals-type-cardinal'];
const parents = JSON.parse(readFileSync(process.argv[3])).supplemental.parentLocales.parentLocale;
const languages = new Set('af am ar az bg bn ca cs da de el en es fa fi fil fr gu he hi hr hu id it ja kn ko lt lv ml mr nb nl pl pt ro ru sk sl sr sv sw ta te th tr uk ur vi zh'.split(' '));
const groups = new Map(), regional = new Map();
for (const [locale, rules] of Object.entries(data)) {
	if (!languages.has(locale.split('-')[0])) continue;
	const tests = Object.entries(rules).map(([key, rule]) => [key.split('-').at(-1), rule.split('@')[0].trim()]).filter(([, rule]) => rule);
	if (!tests.length) continue;
	const key = JSON.stringify(tests);
	const tags = groups.get(key) ?? [];
	tags.push(locale);
	groups.set(key, tags);
	if (locale.includes('-')) {
		regional.set(locale, locale);
		for (const [child, parent] of Object.entries(parents))
			if (parent === locale) regional.set(child, parent);
	}
}
function relation(rule) {
	const match = /^([nivfte])(?: % (\d+))? (!?=) ([\d.,]+)$/.exec(rule);
	if (!match) throw Error(rule);
	const [, operand, mod, operator, ranges] = match;
	const value = operand === 'n' ? 'i' : operand === 't' ? 'f' : operand;
	if (operand === 'e') return ranges.split(',').some(x => x.split('..')[0] === '0') === (operator === '=');
	const expr = !mod ? value : value === 'f' ? `f${mod}` : `(tail % ${mod})`;
	if (mod && (value === 'f' ? !['10', '100'].includes(mod) : 1000000 % Number(mod) !== 0)) throw Error(rule);
	const parts = ranges.split(',').map(range => {
		const [a, b] = range.split('..');
		return b ? `(${expr} >= ${a} && ${expr} <= ${b})` : `${expr} == ${a}`;
	});
	const joined = parts.join(' || ');
	const test = operand === 'n' ? `(v == 0 && ${parts.length > 1 ? '(' + joined + ')' : joined})` : parts.length > 1 ? '(' + joined + ')' : joined;
	return operator === '!=' ? `!(${test})` : test;
}
const condition = rule => rule.split(' or ').map(and => and.split(' and ').map(relation))
	.filter(parts => !parts.includes(false)).map(parts => parts.filter(part => part !== true).join(' && ') || 'true').join(' || ') || 'false';
const cases = [...groups].map(([tests, locales]) => {
	const testsCode = JSON.parse(tests).map(([category, rule]) => `\t\t\t\tif (${condition(rule)}) return "${category}";`).join('\n');
	const lines = [];
	for (let index = 0; index < locales.length; index += 10) lines.push(locales.slice(index, index + 10).map(s => JSON.stringify(s)).join(' | '));
	return `\t\t\tcase ${lines.join('\n\t\t\t\t| ')}:\n${testsCode}`;
}).join('\n');
const regions = [...new Set(regional.values())].map(parent => {
	const tags = [...regional].filter(([, p]) => p === parent).map(([l]) => JSON.stringify(l));
	return `\t\t\tcase ${tags.join(' | ')}: "${parent}";`;
}).join('\n');
writeFileSync(new URL('Cardinals.hx', import.meta.url), `package helder.os.locale;

// Generated from Unicode CLDR 48.2 by gen-plurals.mjs. See LICENSE.cldr.
class Cardinals {
	public static function select(value:Float, tag:String):String {
		if (!Math.isFinite(value)) return "other";
		var parts = Decimal.plain(Math.abs(value)).split(".");
		var whole = parts[0], i = Std.parseFloat(whole);
		var tail = Std.parseInt(whole.substr(Std.int(Math.max(0, whole.length - 6))));
		var fraction = parts[1] ?? "";
		var v = fraction.length, end = v;
		while (end > 0 && fraction.charCodeAt(end - 1) == "0".code) end--;
		v = end;
		fraction = fraction.substr(0, v);
		var f = v == 0 ? 0.0 : Std.parseFloat(fraction);
		var f100 = v == 0 ? 0 : Std.parseInt(fraction.substr(Std.int(Math.max(0, v - 2))));
		var f10 = f100 % 10;
		var base = tag.split("-");
		var regional = (base.length > 1 ? base[0] + "-" + base[1] : base[0]);
		var rule = switch regional {
${regions}
			case _: base[0];
		};
		switch rule {
${cases}
			case _:
		}
		return "other";
	}
}
`);
