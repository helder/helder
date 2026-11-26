// The HTML standard's named character references (entities.json, the
// WHATWG's; the list is closed, so its bytes are pinned by their hash) as
// src/helder/dom/Entities.hx: every name, with its ";" and the legacy ones
// without, and its code points.
//
//   node tests/dom/entities.mjs [entities.json]
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const URL = 'https://html.spec.whatwg.org/entities.json';
const SHA256 = 'd741d877ac77c4194c4ad526b5b4a19aef8dfe411ab840a466891cdbb9f362e6';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const bytes = process.argv[2] ? fs.readFileSync(process.argv[2]) : Buffer.from(await (await fetch(URL)).arrayBuffer());
const hash = crypto.createHash('sha256').update(bytes).digest('hex');
if (hash !== SHA256) throw new Error(`entities.json: sha256 ${hash}, not the pinned ${SHA256}`);
const json = JSON.parse(bytes.toString('utf8'));
const entries = Object.keys(json)
	.sort()
	.map((k) => `${k.slice(1)} ${json[k].codepoints.map((c) => c.toString(16)).join('.')}`);
const data = entries.join(',');
const lines = [];
for (let i = 0; i < data.length; i += 110) lines.push(JSON.stringify(data.slice(i, i + 110)));
const out = `package helder.dom;

// The HTML standard's named character references (entities.json, made by
// tests/dom/entities.mjs; don't edit): "amp; 26", "," between them, "."
// between a reference's code points; a name without its ";" is a legacy one,
// matched without it. Made into a map on the first lookup.
@:noCompletion class Entities {
	public static inline var LONGEST = ${Math.max(...Object.keys(json).map((k) => k.length - 1))};

	static var map:Null<Map<String, String>> = null;

	// the text of a reference's name, with its ";" when it has one (null: none)
	public static function get(name:String):Null<String> {
		if (map == null) map = read();
		return map.get(name);
	}

	static function read():Map<String, String> {
		var m = new Map<String, String>();
		for (entry in DATA.split(",")) {
			var space = entry.indexOf(" ");
			var text = new StringBuf();
			for (h in entry.substr(space + 1).split("."))
				text.addChar(Std.parseInt("0x" + h));
			m.set(entry.substr(0, space), text.toString());
		}
		return m;
	}

	static final DATA = ${lines.join('\n\t\t+ ')};
}
`;
fs.writeFileSync(path.join(root, 'src/helder/dom/Entities.hx'), out);
console.log(`src/helder/dom/Entities.hx: ${entries.length} references`);
