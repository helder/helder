// Audit G 8: a Window made from an options object, its input a property,
// its safe area Edges.
//
//   new Window({title, width, height, ?titlebar, ?transparent})   (WindowOptions)
//   new UiWindow({title, width, height, ?titlebar, ?transparent, ?text, ?antialias})
//   window.input = rects       (was window.input(rects); inputRects read it)
//   window.safe                (Edges, pixels: was safeTop, safeLeft, safeBottom, safeRight)
//
// Edges moves from helder.ui to helder.os, beside Rect, so that a Window's
// safe area and helder.ui's padding and margins are one type.
import { edit, addImport, done } from "./lib.mjs";

const WINDOW = ["title", "width", "height", "titlebar", "transparent"];
const UIWINDOW = ["title", "width", "height", "text", "antialias", "titlebar", "transparent"];

// the arguments of the call whose "(" is at open: [args, the index after ")"]
function args(s, open) {
	const out = [];
	let depth = 0, at = open + 1, i = open;
	for (; i < s.length; i++) {
		const c = s[i];
		if (c === '"' || c === "'" || c === "`") {
			const q = c;
			for (i++; i < s.length && s[i] !== q; i++) if (s[i] === "\\") i++;
			continue;
		}
		if (c === "(" || c === "[" || c === "{") depth++;
		else if (c === ")" || c === "]" || c === "}") {
			depth--;
			if (depth === 0) {
				out.push(s.slice(at, i));
				return [out.map((a) => a.trim()).filter((a, k, all) => a !== "" || all.length > 1), i + 1];
			}
		} else if (c === "," && depth === 1) {
			out.push(s.slice(at, i));
			at = i + 1;
		}
	}
	return null;
}

function construct(s, ts) {
	const re = /\bnew (helder\.os\.Window|helder\.ui\.UiWindow|Window|UiWindow)\(/g;
	let m, out = "", last = 0;
	while ((m = re.exec(s))) {
		const open = m.index + m[0].length - 1, r = args(s, open);
		if (!r) continue;
		const [as, end] = r;
		// (already an options object, or a forwarding call)
		if (as.length === 1 && (as[0].startsWith("{") || !/,/.test(as[0]) && as.length < 3)) continue;
		if (as.length < 3) continue;
		const names = m[1].endsWith("UiWindow") ? UIWINDOW : WINDOW;
		const fields = [];
		as.forEach((a, k) => {
			if (k >= names.length) return;
			if (a === "null" || a === "undefined") return;
			const n = names[k];
			// (TypeScript's TitleBar is its string)
			fields.push(a === n ? n : `${n}: ${a}`);
		});
		out += s.slice(last, open + 1) + "{" + fields.join(", ") + "}";
		last = end - 1;
		re.lastIndex = end;
	}
	return out + s.slice(last);
}

edit(() => true, (s, f) => {
	const hx = f.endsWith(".hx"), ts = /\.(ts|tsx)$/.test(f), md = f.endsWith(".md");
	const platform = /^src\/helder\/os\/(android|apple|windows|linux|web|headless|ios)\//.test(f);
	// (every text file: Haxe written in a script's strings too, the dev tests' programs)
	s = construct(s, ts);
	if (!platform) {
		// (the safe area)
		s = s.replace(/\b([\w.()\]]+)\.safe(Top|Left|Bottom|Right)\b/g, (all, w, side) => (/^(ios|android)\(\)$/.test(w) ? all : `${w}.safe.${side.toLowerCase()}`));
		s = s.replace(/\bWindow\.safeTop\b(\.\.\.)?/g, "Window.safe");
		// (input)
		s = s.replace(/\b(window|w\.window|w)\.input\(([^;\n]*)\);/g, (all, w, a) => (/^\[?\s*(null|\[|\{|for\b|x\b)/.test(a) || a === "null" ? `${w}.input = ${a};` : all));
		s = s.replace(/\.inputRects\b/g, ".input");
		s = s.replace(/`window\.input\(rects\)`/g, "`window.input = rects`");
	}
	// (Edges: helder.os's)
	s = s.replace(/\bhelder\.ui\.Edges\b/g, "helder.os.Edges");
	// (a bare Edges in code: imported, unless it is; studio's own Edges, a typedef of its package, stays)
	if (hx && !f.startsWith("apps/studio/") && f !== "src/helder/os/Edges.hx"
		&& s.split("\n").some((l) => !/^\s*\/\//.test(l) && /(?<![.\w])Edges\b/.test(l))) {
		const pack = /^package ([\w.]*);/m.exec(s)?.[1] ?? "";
		const sees = /^import helder\.os\.(\*|Edges);/m.test(s) || pack === "helder.os";
		if (!sees) s = addImport(s, "import helder.os.Edges;");
	}
	if (ts) s = s.replace(/^import \{([^}]*)\bEdges\b([^}]*)\} from (["'])helder\/ui\3/m, (all) => all); // (no TypeScript program imports it)
	return s;
});
// (Edges declared by helder/os alone: out of helder/ui's classes, wherever in the list)
edit((f) => f === "src/helder/ui/TypeScript.hx", (s) =>
	s.replace(/\bhelder\.(?:ui|os)\.Edges,\s*/g, "").replace(/,\s*helder\.(?:ui|os)\.Edges\b/g, "").replace(/^import helder\.os\.Edges;\r?\n\r?\n?/m, ""));
// (<Surface>'s comment back on SurfaceProps, UiWindowOptions before it)
edit((f) => f === "src/helder/ui/UiWindow.hx", (s) =>
	s.replace("// <Surface>'s props (UiWindow.Surface)\n// what a UiWindow is made with:", "// what a UiWindow is made with:")
		.replace(/(\n\}\n\n)typedef SurfaceProps = \{/, (m, a) => (s.includes("// <Surface>'s props (UiWindow.Surface)\ntypedef SurfaceProps") ? m : `${a}// <Surface>'s props (UiWindow.Surface)\ntypedef SurfaceProps = {`)));
edit((f) => f === "src/helder/os/TypeScript.hx", (s) => s.replace("@:typescript.classes(helder.os.Store,", "@:typescript.classes(helder.os.Edges, helder.os.Store,"));
done("08-window");
