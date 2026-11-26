package helder.ui.flow;

import helder.ui.box.Box;

// The absolutely positioned boxes waiting for their containing block
// (CSS 2.1 §10.1: the nearest positioned ancestor's padding box, else the
// initial containing block): each with its static position, in the
// fragment of the block it would have been in (§10.3.7's and §10.6.4's
// static position).
class Positioned {
	public final boxes:Array<Box> = [];
	public final fragments:Array<Int> = [];
	public final xs:Array<Float> = [];
	public final ys:Array<Float> = [];

	public function new() {}

	public function add(box:Box, fragment:Int, x:Float, y:Float) {
		boxes.push(box);
		fragments.push(fragment);
		xs.push(x);
		ys.push(y);
	}
}
