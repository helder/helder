package studio;

import haxe.io.Bytes;
import helder.image.Image;
import helder.test.Test;
import helder.ui.draw.FrameArchive;
import helder.ui.draw.FrameWriter;

function tests() {
	describe("Density", () -> {
		function still(f:FrameWriter->Void) {
			var w = new FrameWriter(), a = new FrameArchive();
			w.rect(0, 0, 400, 200, 0, 0xFF102030, 0, 0);
			f(w);
			a.add("s", "", 400, 200, w.frame());
			return a.list("s");
		}
		test("a scene's picture: the pixels a point it holds", () -> {
			var l = still(w -> {
				w.pushTransform(0.5, 0, 0, 0.5, 0, 0);
				w.image(new Image(400, 200, Bytes.alloc(400 * 200 * 4)), 0, 0, 400, 200, 0, 0, 1, 1, 0);
				w.popTransform();
			});
			equals(Density.of(l), 2.0);
		});
		test("vectors alone: sharp at any zoom", () -> {
			equals(Density.of(still(_ -> {})), Math.POSITIVE_INFINITY);
		});
	});
}
