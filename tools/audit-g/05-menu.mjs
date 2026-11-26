// Audit G 5: one Menu model, helder.ui.menu's: Menu, MenuItem (Item,
// Separator, Submenu, Role) and MenuRole, shown by Menus (popup, a
// MenuBar, <MenuBarView>). TypeScript has all of it in helder/ui, as the
// types already were: item(label, action), separator(), submenu, role,
// popup and resolve are helder/ui's, not helder/ui/actions'; helder/ui/
// actions' own MenuBar class is gone (<MenuBarView> is the bar), as is the
// menu half of its runtime (helder.ui.actions.Script). helder/ui/actions
// is the actions alone.
import { edit, ts, done } from "./lib.mjs";

const MENU = new Set(["item", "separator", "submenu", "role", "popup", "resolve", "Menu", "MenuItem", "PlatformMenuItem"]);
edit((f) => ts(f) || f.endsWith(".md"), (s) => {
	let moved = [];
	s = s.replace(/^import (type )?\{([^}]*)\} from (["'])helder\/ui\/actions\3;?/gm, (all, typeOnly, names, q) => {
		const segs = names.split(",");
		const name = (p) => p.trim().replace(/^type\s+/, "");
		const menu = segs.filter((p) => MENU.has(name(p))).map((p) => p.trim());
		if (menu.length === 0) return all;
		moved = moved.concat(menu.map((p) => (typeOnly && !p.startsWith("type ") ? "type " : "") + p));
		let rest = segs.filter((p) => !MENU.has(name(p)));
		if (rest.length) rest[rest.length - 1] = rest[rest.length - 1].replace(/\s*$/, /\s*$/.exec(segs[segs.length - 1])[0]);
		const semi = all.trimEnd().endsWith(";") ? ";" : "";
		return rest.some((p) => p.trim()) ? `import ${typeOnly ?? ""}{${rest.join(",")}} from ${q}helder/ui/actions${q}${semi}` : "\0drop";
	});
	if (moved.length === 0) return s;
	// (into the import of helder/ui, else one of its own where that was)
	const ui = /^import \{([^}]*)\} from (["'])helder\/ui\2/m;
	if (ui.test(s)) s = s.replace(ui, (m, names, q) => `import {${names.replace(/\s*$/, "")}, ${moved.join(", ")}${/\s$/.test(names) ? " " : ""}} from ${q}helder/ui${q}`).replace(/^\0drop;?\r?\n/m, "");
	else if (s.includes("\0drop")) s = s.replace("\0drop", `import { ${moved.join(", ")} } from "helder/ui";`);
	else s = s.replace(/^import [^;]*?from (["'])helder\/ui\/actions\1;?\r?\n/m, (m) => m + `import { ${moved.join(", ")} } from "helder/ui";\n`);
	// (separator a function, as the other builders: outside the imports)
	if (moved.includes("separator"))
		s = s.split("\n").map((l) => (/^import\b/.test(l) ? l : l.replace(/\bseparator\b(?!\s*[(:])(?=\s*[,\]\)])/g, "separator()"))).join("\n");
	return s;
});
edit((f) => f === "src/helder/ui/README.md", (s) => s.replace("menus' `item(label, action)`,\n`resolve`, `popup`, `MenuBar`)", "helder/ui's menus, `item(label,\naction)`, `popup`, `<MenuBarView>`)"));
done("05-menu");
