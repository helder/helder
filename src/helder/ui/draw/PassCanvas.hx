package helder.ui.draw;

import helder.os.Edges;
import helder.gfx.Color;
import helder.gfx.Texture;
import helder.image.Image;
import helder.ui.*;

// A list read from a frame of data (FrameReader with passes) replayed onto
// c: its calls c's, but the GPU textures it marks for what passes draw as
// data (PassData.MARK less their index), drawn by draw (onto c, in their
// place, under the clips and transforms in effect there)
//
//   list.replay(new PassCanvas(c, (k, x, y, w, h) -> scenes[k].draw(c, x, y, w, h)));
class PassCanvas implements TextureCanvas {
	final c:Canvas;
	final g:Null<TextureCanvas>;
	final draw:(index:Int, x:Float, y:Float, w:Float, h:Float) -> Void;

	public function new(c:Canvas, draw:(index:Int, x:Float, y:Float, w:Float, h:Float) -> Void) {
		this.c = c;
		g = Std.downcast(c, TextureCanvas);
		this.draw = draw;
	}

	public function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners) {
		if (id <= PassData.MARK) draw(PassData.MARK - id, x, y, w, h) else if (g != null) g.gpuTexture(t, id, x, y, w, h, radius, corners);
	}

	public function translate(dx:Float, dy:Float)
		c.translate(dx, dy);

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners)
		c.pushClip(x, y, w, h, radius, corners);

	public function popClip()
		c.popClip();

	public function pushOpacity(alpha:Float)
		c.pushOpacity(alpha);

	public function pushGroup(alpha:Float, x:Float, y:Float, w:Float, h:Float)
		c.pushGroup(alpha, x, y, w, h);

	public function popOpacity()
		c.popOpacity();

	public function pushTransform(a:Float, b:Float, cc:Float, d:Float, e:Float, f:Float)
		c.pushTransform(a, b, cc, d, e, f);

	public function popTransform()
		c.popTransform();

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges,
			style:BorderStyle = Solid)
		c.rect(x, y, w, h, radius, fill, borderWidth, border, corners, sides, style);

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>)
		c.shadow(x, y, w, h, radius, color, blur, corners, offset);

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners)
		c.insetShadow(x, y, w, h, radius, color, blur, dx, dy, spread, corners);

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke)
		c.path(p, fill, stroke);

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners)
		c.image(img, x, y, w, h, u0, v0, u1, v1, radius, corners);

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>)
		c.text(p, x, y, width, align, color, colors);

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>)
		c.textShadow(p, x, y, width, align, color, blur, colors);

	public function pass(f:Any)
		if (g != null) g.pass(f);

	public function slot(s:LayerSlot, x:Float, y:Float, w:Float, h:Float)
		if (g != null) g.slot(s, x, y, w, h);

	// (a list replayed whole: no layers of its own)
	public function layerTiles(l:Layer):Bool
		return false;

	public function keeps():Bool
		return false;

	public function damage(d:Damage) {}

	public function redraw(i:Int) {}

	public function composites():Bool
		return false;

	public function enter(n:Node, kind:Int):Bool
		return false;

	public function mover(m:Mover):Bool
		return false;

	public function leave() {}
}
