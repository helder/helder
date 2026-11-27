package helder.ui.flow;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;

// A paged document's fixed boxes, on every page (Paged Media 3 §3.3),
// their containing block the first page's area (the viewport, as
// Chromium has it: on a page of another size too), and each one's static
// place in the page area where layout came to it, for the pages that don't.
class Repeated {
	public final boxes:Array<Box>;
	public final width:Float;
	public final height:Float;
	public final places = new ObjectMap<Box, {x:Float, y:Float}>();

	public function new(boxes:Array<Box>, width:Float, height:Float) {
		this.boxes = boxes;
		this.width = width;
		this.height = height;
	}
}
