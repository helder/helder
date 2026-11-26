// Audit G 9: the media Player's state as Reads (helder.view.graph), as the
// rest of helder exposes what changes: duration, loaded, error, ended,
// playing and time are Read<T>, called to read (p.time(), tracked where
// a hole or effect reads it). The controls (rate, volume, muted, loop)
// stay fields to set; media, video, audio, unheard and shown are what
// was loaded and the frame shown.
//
// A Player's reads are renamed where the variable is one: from its
// declaration (var p = Player.open(...), p:Player, var p = x.player, a
// loop over Player.live) to the end of its block, and x.player.<state>
// chains; a packet's p.time elsewhere in the same file stays.
import { edit, done } from "./lib.mjs";

const STATE = "(time|duration|loaded|error|playing|ended)";
const DECL = [
	/\bvar ([a-z]\w*)\s*=\s*(?:helder\.media\.)?Player\.open\(/,
	/\b([a-z]\w*)\s*=\s*(?:helder\.media\.)?Player\.open\(/,
	/\b(?:var |final )?([a-z]\w*)\s*:\s*(?:Null<)?(?:helder\.media\.)?Player\b/,
	/\bvar ([a-z]\w*)\([\w, ]*\)\s*:\s*(?:Null<)?(?:helder\.media\.)?Player\b/,
	/\bvar ([a-z]\w*)\s*=\s*(?:[\w.]+\.)?player\b(?!\.)/,
	/\bvar ([a-z]\w*)\s*=[^;]*\.player\s*;/,
	/\bfor \(([a-z]\w*) in (?:@:privateAccess )?(?:helder\.media\.)?Player\.live\)/,
];

function rename(s) {
	const lines = s.split("\n");
	// (each declaration: the lines to its block's end)
	for (let i = 0; i < lines.length; i++) {
		for (const d of DECL) {
			const m = d.exec(lines[i]);
			if (!m) continue;
			const name = m[1], re = new RegExp(`\\b${name}\\.${STATE}\\b(?!\\s*\\()`, "g");
			let depth = 0;
			// (the name declared again, not as a Player: its region ends there)
			const again = new RegExp(`\\bvar\\b[^;]*\\b${name}\\b\\s*[=;,:]|\\bfor \\(${name} in\\b|\\(${name} = (?!(?:helder\\.media\\.)?Player\\.open)`);
			for (let j = i; j < lines.length; j++) {
				if (j > i && again.test(lines[j]) && !DECL.some((d) => d.test(lines[j]))) break;
				const from = j === i ? m.index : 0;
				lines[j] = lines[j].slice(0, from) + lines[j].slice(from).replace(re, `${name}.$1()`);
				for (const c of lines[j].replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\/\/.*$/g, "")) {
					if (c === "{") depth++;
					else if (c === "}") depth--;
				}
				if (depth < 0) break;
			}
		}
	}
	return lines.join("\n").replace(new RegExp(`(\\.player)\\.${STATE}\\b(?!\\s*\\()`, "g"), "$1.$2()");
}

const PLAYERS = /\bPlayer\b|\.player\b/;
edit((f) => f.endsWith(".hx") && f !== "src/helder/media/Player.hx", (s) => (PLAYERS.test(s) ? rename(s) : s));
done("09-player");
