package viewer;

import helder.ui.Canvas;
import helder.ui.Path;

// The player's icons drawn as paths in the text's colour (no SVG parsed:
// lucide's play, pause, volume-2 and volume-x, on their 24 by 24 grid)
class MediaIcon extends helder.ui.Node {
	public var kind(default, set):String;

	public function new(kind:String) {
		super("icon");
		this.kind = kind;
	}

	function set_kind(k:String):String {
		if (k != kind && ui != null) {
			layerChanged();
			ui.requestFrame();
		}
		return kind = k;
	}

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var k = Math.min(width, height) / 24, c = textColor();
		canvas.pushTransform(k, 0, 0, k, x + (width - 24 * k) / 2, y + (height - 24 * k) / 2);
		switch kind {
			case "play":
				canvas.path(new Path().moveTo(6, 3).lineTo(20, 12).lineTo(6, 21).close(), c);
			case "pause":
				canvas.path(new Path().rect(6, 4, 4, 16, 1).rect(14, 4, 4, 16, 1), c);
			case _:
				var line = {width: 2.0, paint: (c : helder.ui.Paint), cap: helder.ui.LineCap.Round, join: helder.ui.LineJoin.Round};
				canvas.path(new Path().moveTo(11, 5).lineTo(6, 9).lineTo(2, 9).lineTo(2, 15).lineTo(6, 15).lineTo(11, 19).close(), null, line);
				if (kind == "muted") canvas.path(new Path().moveTo(16, 9).lineTo(22, 15).moveTo(22, 9).lineTo(16, 15), null, line);
				else canvas.path(new Path().moveTo(15.5, 8.5).arcTo(5, 5, 0, false, true, 15.5, 15.5).moveTo(19, 5).arcTo(10, 10, 0, false, true, 19, 19), null, line);
		}
		canvas.popTransform();
	}
}
