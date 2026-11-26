// WHATWG Encoding's labels and single-byte indexes as
// src/helder/css/EncodingData.hx (Css.decode's): every label to its
// encoding's name, and each single-byte encoding's bytes 0x80 to 0xFF as
// a string of 128 code points (U+FFFD where the index has none).
//
//   node tests/css/make-encodings.mjs <encodings.json> <indexes.json>
//
// (both from https://encoding.spec.whatwg.org/, BSD-3-Clause)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const [encodingsPath, indexesPath] = process.argv.slice(2);
if (!indexesPath) throw new Error('usage: node make-encodings.mjs <encodings.json> <indexes.json>');
const groups = JSON.parse(fs.readFileSync(encodingsPath, 'utf8'));
const indexes = JSON.parse(fs.readFileSync(indexesPath, 'utf8'));

const labels = [];
const single = [];
for (const g of groups)
	for (const e of g.encodings) {
		const name = e.name.toLowerCase();
		labels.push(`\t\t\tcase ${e.labels.map((l) => JSON.stringify(l)).join(' | ')}: "${name}";`);
		if (g.heading === 'Legacy single-byte encodings') {
			// (ISO-8859-8-I decodes as ISO-8859-8: only its direction differs)
			const index = indexes[name === 'iso-8859-8-i' ? 'iso-8859-8' : name];
			if (!index || index.length !== 128) throw new Error(`no index for ${name}`);
			const text = index.map((c) => '\\u' + (c ?? 0xfffd).toString(16).toUpperCase().padStart(4, '0')).join('');
			single.push(`\t\t\tcase "${name}": "${text}";`);
		}
	}

const out = `package helder.css;

// WHATWG Encoding's labels to their encodings' names and its single-byte
// encodings' bytes 0x80 to 0xFF; made by tests/css/make-encodings.mjs
class EncodingData {
	// (switches, not maps: nothing made or initialized before the first use)
	public static function name(label:String):Null<String>
		return switch label {
${labels.join('\n')}
			default: null;
		}

	public static function single(name:String):Null<String>
		return switch name {
${single.join('\n')}
			default: null;
		}
}
`;
fs.writeFileSync(path.join(here, '../../src/helder/css/EncodingData.hx'), out);
console.log(`${labels.length} encodings' labels, ${single.length} single-byte encodings`);
