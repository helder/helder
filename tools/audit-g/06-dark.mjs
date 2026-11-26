// Audit G 6: one way to read dark mode, one to set it.
//
//   read    helder.os's Settings.dark (Read<Bool>: the system's appearance,
//           kept current by events), and a Ui's own ui.dark (its window's)
//   set     a <Surface dark={...}> (a window's own; without it the window
//           follows Settings.dark)
//
// Gone: UiWindow.dark (a second Signal of the system's appearance, polled
// every second: Settings.dark), Theme.appearance (Theme.c reads the
// screen's, ScreenContext.dark, which the window writes) and the public
// App.prefersDark (Settings' source, @:noCompletion).
import { edit, addImport, done } from "./lib.mjs";

edit(() => true, (s, f) => {
	const hx = f.endsWith(".hx"), ts = /\.tsx?$/.test(f);
	s = s.replace(/\bhelder\.ui\.UiWindow\.dark\b/g, "helder.os.Settings.dark");
	if (hx || ts) {
		const before = s;
		s = s.replace(/\bUiWindow\.dark\b/g, "Settings.dark");
		// (a bare Settings.dark: imported, unless it is)
		if (hx && s.split("\n").some((l) => !/^\s*\/\//.test(l) && /(?<![.\w])Settings\.dark\b/.test(l)) && !/^import helder\.os\.(Settings|\*);/m.test(s) && !/^package helder\.os;/m.test(s))
			s = addImport(s, "import helder.os.Settings;");
		if (s !== before && ts && !/^import [^\n]*\bSettings\b[^\n]*from ["']helder\/os["']/m.test(s)) {
			// (into its import of helder/os, else one of its own)
			const os = /^import \{([^}]*)\} from (["'])helder\/os\2/m;
			s = os.test(s) ? s.replace(os, (m, names, q) => `import {${names.replace(/\s*$/, "")}, Settings${/\s$/.test(names) ? " " : ""}} from ${q}helder/os${q}`)
				: s.replace(/^(import [^\n]*\n)/m, `import { Settings } from "helder/os";\n$1`);
		}
	}
	// (Theme.c follows the window's dark itself)
	s = s.replace(/^[ \t]*\/\/ \(the colours given inline follow the appearance chosen, as the sheet's do\)\r?\n(?=[ \t]*Theme\.appearance)/m, "");
	s = s.replace(/^[ \t]*Theme\.appearance = \(\) => [^;\n]*;?\r?\n/gm, "").replace(/^[ \t]*Theme\.appearance = \(\) -> [^;\n]*;\r?\n/gm, "");
	// (Settings itself reads it)
	if (!f.startsWith("src/helder/os/")) s = s.replace(/\bApp\.prefersDark\(\)/g, "Settings.dark.peek()");
	return s;
});
done("06-dark");
