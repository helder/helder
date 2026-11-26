package studio;

import helder.test.Test;

function tests() {
	describe("Studio", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		test("a source edited on disk, not a story's or a design's: an edit of the history", async(() -> Temp.within("helder-disk", dir -> {
			Files.save('$dir/app.helder', sys.io.File.getContent("../../tests/studio/design/app.helder"));
			Files.save('$dir/paper.ts', "export const fold = 1;\n");
			var s = new Studio(dir, {});
			s.scanDisk();
			// (within the same second: its size tells it apart)
			Files.save('$dir/paper.ts', "export const fold = 22;\n");
			s.scanDisk();
			var e = s.docs.nextUndo();
			equals([e?.file, e?.label], [s.project.dir + "/paper.ts", "the file changed on disk"]);
			equals(s.docs.get(s.project.dir + "/paper.ts").text, "export const fold = 22;\n");
		})));
		test("a frame's bar: its label, Play from here (a scenario's boot, then the app's main), Ask's chip, Code at its line",
			async(() -> Temp.within("helder-bar", dir -> {
				Files.save('$dir/main.tsx', 'import { UiWindow } from "helder/ui";\nimport { App } from "./app";\n\nUiWindow.run(<App/>);\n');
				Files.save('$dir/app.tsx', 'import { signal } from "helder/view";\n\nexport const sky = signal("day");\nexport function App() {\n\treturn <view/>;\n}\n');
				Files.save('$dir/app.scenario.tsx', 'import { scenario } from "helder/scenario";\nimport { sky } from "./app";\n\n// the beam at dusk\n'
					+ 'export const dusk = scenario({ name: "Harbour at night/Dusk sweep", loop: 7, boot() { sky("dusk"); } });\n');
				if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
				Starter.config(dir);
				var s = new Studio(dir, {}), name = "Harbour at night/Dusk sweep";
				equals(SelectionBar.parts(s.project, name), {label: "Harbour at night · Dusk sweep", play: true, loop: 7.0});
				s.focus(name, false);
				helder.view.graph.Graph.flush();
				equals(SelectionBar.selected(s), [name]);
				var entry = s.playEntry(s.project.screen(name));
				equals(Files.read(entry).indexOf('import "./.helder-play-boot";\nimport "./main";\n') > 0, true);
				equals(Files.read('${s.project.dir}/${Studio.BOOT}').indexOf('import { dusk } from "./app.scenario";\n\nboot(dusk);\n') > 0, true);
				s.clearAbout();
				helder.view.graph.Graph.flush();
				equals([s.about(), s.focused.peek()], [null, name]);
				s.askAbout(name);
				helder.view.graph.Graph.flush();
				equals(s.about(), name);
				s.codeOf(name);
				helder.view.graph.Graph.flush();
				equals(s.talk.reading.peek(), {file: s.project.dir + "/app.scenario.tsx", line: 5});
			})));
		#end
	});
}
