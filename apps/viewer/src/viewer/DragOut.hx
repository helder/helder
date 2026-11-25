package viewer;

import helder.image.Image;
import helder.image.Resize;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.Popup;
import viewer.Drops.DragFiles;

// Files dragged from the browser: a press on an entry moved 4 points
// carries the selection (or the entry alone, when it is not selected) as
// helder.ui's drag, its picture following the pointer, onto a folder of
// the window (Drops: moved, Option or Alt copied); once the pointer leaves
// the window, handed to the system's (Ui.dragFiles) for other apps: a file
// manager, mail, chat, a browser's upload; a move a target made shows when
// the folder is read again. (The web's files are on no disk: none leave it.)
class DragOut {
	public static function from(x:Explorer, n:Node, name:Void->String) {
		n.dragData = {};
		n.onDragStart = _ -> {
			var b = x.browser, which = name(), picked = b.picked();
			var names = picked.contains(which) ? picked : [which];
			var paths = [for (m in names) b.path(m)];
			var local = [for (p in paths) x.files.localPath(p)].filter(p -> p != null);
			var drag:DragFiles = {paths: paths, local: local, external: false};
			n.dragData = drag;
			var entry = b.entry(which), image = entry == null ? null : Tiles.cached(x, entry);
			if (image != null) {
				var small = Resize.toFit(image.pixels, image.width, image.height, 96, 96);
				image = new Image(small.width, small.height, small.rgba);
			}
			follow(x, n, drag, image, names.length);
		};
		n.onDragEnd = _ -> n.dragData = {};
	}

	// (while it lasts: its picture at the pointer; out of the window, the system's drag)
	static function follow(x:Explorer, n:Node, drag:DragFiles, image:Null<Image>, count:Int) {
		var ui = n.ui;
		if (ui == null) return;
		var ghost = new Popup("drag-ghost");
		ghost.placement = Manual;
		ghost.style.set({pointerEvents: None, opacity: 0.85, alignItems: Center});
		if (image != null) {
			var pic = new helder.ui.ImageNode(image);
			pic.style.set({width: image.width, height: image.height, radius: 6});
			ghost.append(pic);
		}
		if (count > 1) {
			var badge = new helder.ui.TextNode(Std.string(count));
			badge.style.set({position: Absolute, right: -6, top: -6, minWidth: 20, height: 20, padding: [0, 6], radius: 10, background: 0xFFFF3B30,
				color: 0xFFFFFFFF, fontSize: 12, fontWeight: 600, textAlign: Center});
			ghost.append(badge);
		}
		ui.open(ghost);
		Clock.add(_ -> {
			var d = ui.dragging;
			if (d == null || d.data != drag) {
				ui.close(ghost);
				return false;
			}
			var w = image == null ? 0.0 : image.width / 2, h = image == null ? 0.0 : image.height / 2;
			ghost.style.left = d.x - w;
			ghost.style.top = d.y - h;
			ui.requestFrame();
			if (d.x >= 0 && d.y >= 0 && d.x < ui.width && d.y < ui.height) return true;
			ui.close(ghost);
			#if (hxmc.target != "wasm32-wasi")
			// (out of the window: the system's drag, which ends this one)
			if (drag.local.length > 0)
				ui.dragFiles(drag.local, image, w, h, [Copy, Move], op -> if (op == Move) x.browser.refresh());
			#end
			return false;
		});
	}
}
