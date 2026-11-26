package studio;

import helder.gfx.Color;
import helder.image.Image;
import helder.os.Edges;
import helder.ui.*;
import helder.ui.draw.DisplayList;

// The pixels a point a still's images hold (a scene's picture: its pixels
// at Host.CAPTURE), the least of them; infinity when it has none (its
// vectors sharp at any zoom). Deeper than that, only its program draws it
// sharper (Studio.showVisible wakes it).
class Density implements Canvas {
	public static function of(list:DisplayList):Float {
		var d = new Density();
		list.replay(d);
		return d.least;
	}

	var least = Math.POSITIVE_INFINITY;
	var k = 1.0;
	final ks:Array<Float> = [];

	function new() {}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {
		var shown = Math.abs(w) * k;
		if (shown > 0) least = Math.min(least, img.width * Math.abs(u1 - u0) / shown);
	}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		ks.push(k);
		k *= Math.sqrt(Math.abs(a * d - b * c));
	}

	public function popTransform()
		k = ks.pop() ?? 1.0;

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {}

	public function popClip() {}

	public function pushOpacity(alpha:Float) {}

	public function pushGroup(alpha:Float, x:Float, y:Float, w:Float, h:Float) {}

	public function popOpacity() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges,
		style:BorderStyle = Solid) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
		?corners:Corners) {}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {}
}
