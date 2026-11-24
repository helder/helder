package viewer;

import helder.image.Resize;
import helder.os.DragOperation;
import helder.ui.Node;

// Files dragged out of the browser to other apps (Ui.dragFiles: the
// system's drag): a press on an entry moved 4 points carries the
// selection (or the entry alone, when it is not selected), its picture the
// entry's thumbnail; a move a target made shows when the folder is read again.
class DragOut {
	public static function from(x:Explorer, n:Node, name:Void->String) {
		var fromX = 0.0, fromY = 0.0, gone = false;
		n.onPointerDown = e -> {
			fromX = e.x;
			fromY = e.y;
			gone = false;
		};
		n.onPointerMove = e -> {
			if (gone || !n.pressed || n.ui == null) return;
			var dx = e.x - fromX, dy = e.y - fromY;
			if (dx * dx + dy * dy < 16) return;
			gone = true;
			try start(x, n, name()) catch (_:Dynamic) {}
		};
	}

	static function start(x:Explorer, n:Node, which:String) {
		var b = x.browser, picked = b.picked();
		var names = picked.contains(which) ? picked : [which];
		var paths = [for (m in names) x.files.localPath(b.path(m))].filter(p -> p != null);
		if (paths.length == 0) return;
		var entry = b.entry(which), image = entry == null ? null : Tiles.cached(x, entry);
		if (image != null) {
			var small = Resize.toFit(image.pixels, image.width, image.height, 96, 96);
			image = new helder.image.Image(small.width, small.height, small.rgba);
		}
		// (the picture held at its middle, as Finder holds an icon)
		n.ui.dragFiles(paths, image, image == null ? 0 : image.width / 2, image == null ? 0 : image.height / 2, [Copy, Move],
			op -> if (op == Move) b.refresh());
	}
}
