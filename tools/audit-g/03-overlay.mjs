// Audit G 3: helder.scene's lines drawn over everything, not depth tested:
// Lines' option and field onTop, DebugDraw.onTop and Debug.onTop are
// overlay. (A window kept over the others, helder.os's Window.onTop and
// helder.ui's Surface onTop, is another concept and keeps its name.)
import { edit, done } from "./lib.mjs";

// (helder.scene and the programs that draw its lines: every onTop there is theirs)
const SCENE = ["src/helder/scene/", "tests/3d/", "docs/examples/scene-", "examples/picking/"];
edit((f) => SCENE.some((p) => f.startsWith(p)), (s) =>
	s.split("\n").map((l) => {
		// (a comment aligned after it keeps its column: two spaces fewer before it, where there are)
		const n = (l.match(/\bonTop\b/g) ?? []).length;
		if (n === 0) return l;
		const t = l.replace(/\bonTop\b/g, "overlay");
		return t.replace(/ {3,}(?=\/\/|drawn )/, (sp) => sp.slice(0, Math.max(1, sp.length - 2 * n)));
	}).join("\n"));
done("03-overlay");
