package viewer;

import helder.ui.Event;
import helder.os.Mods;
import helder.ui.Node;
import helder.ui.Ui;

// what a drag carries: the files' paths in the browser, on disk (a drag
// out of the window: the system's), and whether they came from another app
typedef DragFiles = {paths:Array<String>, local:Array<String>, external:Bool};

// Folders that files are dropped on (a folder's tile, row, sidebar row: the
// files moved into it, Option or Alt held a copy, as Finder; the folder's
// own space, the folder shown): highlighted while a drag is over them.
// Dropped from another app (the system's drop, Drops.external), copied in.
class Drops {
	// n a folder to drop on (pathOf: its path; null, not one now: a file's tile)
	public static function folder(x:Explorer, n:Node, pathOf:Void->Null<String>) {
		n.onDragOver = e -> {
			var p = pathOf(), d = files(e.data);
			// (none to take: the folder itself among them, or all in it already)
			if (p == null || d == null || d.paths.contains(p) || !Lambda.exists(d.paths, q -> Browser.parent(q) != p)) return;
			e.preventDefault();
			mark(n, true);
		};
		n.onDragLeave = _ -> mark(n, false);
		n.onDrop = e -> {
			mark(n, false);
			var p = pathOf(), d = files(e.data);
			if (p == null || d == null) return;
			x.browser.transfer(d.paths, p, d.external || e.mods & Mods.ALT != 0);
		};
	}

	// the system's drop at x, y (window points) of another app's files: on a
	// folder to drop on, copied into it (true); else false
	public static function external(x:Explorer, ui:Ui, paths:Array<String>, px:Float, py:Float):Bool {
		var n = ui.root.hitTest(px, py);
		while (n != null && n.onDrop == null)
			n = n.parent;
		if (n == null) return false;
		var e = Event.of(Drop, n, px, py);
		e.data = ({paths: paths, local: paths, external: true} : DragFiles);
		n.onDrop(e);
		return true;
	}

	static function files(data:Dynamic):Null<DragFiles>
		return data != null && Reflect.hasField(data, "paths") && Reflect.hasField(data, "external") ? data : null;

	// (the target shown: a mark over it, its radius, the accent's tint and ring)
	static function mark(n:Node, on:Bool) {
		var m = n.find("drop-mark");
		if (!on) {
			if (m != null) n.remove(m);
			return;
		}
		if (m != null) return;
		m = new Node("drop-mark");
		m.style.set({position: Absolute, left: 0, top: 0, right: 0, bottom: 0, pointerEvents: None, radius: n.style.radius,
			background: 0x220A84FF, borderWidth: 2, borderColor: 0xFF0A84FF});
		n.append(m);
	}
}
