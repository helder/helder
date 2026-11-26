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
		#end
	});
}
