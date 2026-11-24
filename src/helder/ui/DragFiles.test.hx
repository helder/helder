package helder.ui;

import helder.os.DragOperation;
import helder.test.Test;

// Ui.dragFiles: the window host's system drag started from a press being
// moved, the press (and a drag of ui's own) let go, no click after; no
// window: false (natively and as wasm32-wasi)
function tests() {
	describe("Ui.dragFiles", () -> {
		var ui:Ui = null, a:Node = null, host:Host = null, log:Array<String> = [];
		beforeEach(() -> {
			ui = new Ui(null, 300, 200);
			host = new Host();
			ui.window = host;
			log = [];
			a = new Node("a");
			a.style.width = 100;
			a.style.height = 50;
			ui.root.append(a);
			a.onClick = e -> log.push("click");
			a.onPointerCancel = e -> log.push("cancel");
			ui.update();
		});
		test("no window: false", () -> {
			ui.window = null;
			equals(ui.dragFiles(["/tmp/a.jpg"], null, 0, 0, [Copy], op -> {}), false);
		});
		test("from a move: the press let go, no click, done with the target's operation", () -> {
			var got:Null<DragOperation> = null;
			a.onPointerMove = e -> if (a.pressed) ui.dragFiles(["/tmp/a.jpg", "/tmp/b.jpg"], null, 4, 6, [Copy, Move], op -> got = op);
			ui.pointerDown(10, 10, 1);
			equals(a.pressed, true);
			ui.pointerMove(30, 10);
			equals([a.pressed, ui.capture == null], [false, true]);
			ui.pointerUp(30, 10, 1);
			equals(log, ["cancel"]);
			equals(host.paths, ["/tmp/a.jpg", "/tmp/b.jpg"]);
			host.done(Move);
			equals(got, Move);
		});
		test("from a DragStart: no drag of ui's own", () -> {
			a.dragData = "a";
			a.onDragStart = e -> ui.dragFiles(["/tmp/a.jpg"], null, 0, 0, [Copy], op -> {});
			ui.pointerDown(10, 10, 1);
			ui.pointerMove(30, 10);
			equals([ui.dragging == null, a.pressed], [true, false]);
			equals(host.paths, ["/tmp/a.jpg"]);
		});
		test("the system refused: the press stays", () -> {
			host.refuse = true;
			a.onPointerMove = e -> if (a.pressed) ui.dragFiles(["/tmp/a.jpg"], null, 0, 0, [Copy], op -> {});
			ui.pointerDown(10, 10, 1);
			ui.pointerMove(30, 10);
			equals(a.pressed, true);
			ui.pointerUp(30, 10, 1);
			equals(log, ["click"]);
		});
	});
}

private class Host implements WindowHost {
	public var paths:Array<String> = [];
	public var done:DragOperation->Void = op -> {};
	public var refuse = false;

	public function new() {}

	public function controls():String
		return "";

	public function systemControls():Null<Bounds>
		return null;

	public function placeControls(x:Float, y:Float) {}

	public function minimize() {}

	public function maximized():Bool
		return false;

	public function maximize(on:Bool) {}

	public function close() {}

	public function dragFiles(paths:Array<String>, image:Null<helder.image.Image>, offsetX:Float, offsetY:Float, allowed:Array<DragOperation>,
			done:DragOperation->Void):Bool {
		if (refuse) return false;
		this.paths = paths;
		this.done = done;
		return true;
	}
}
