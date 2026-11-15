package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.render.PostEffects;

// Colour grading by a lookup table, a PostProcess's (post.lut): a size cubed
// table (16 or 32) as a 2D strip of size slices side by side (size^2 by
// size texels: red across a slice, green down it, blue by slice; gfx has no
// 3D textures), read once in the composite after the curve and the grade,
// display values in and out (an identity strip graded in an image editor,
// as Unreal's and Unity's LUT strips are):
//
//   post.lut = Lut.fromImage(device, image);                 // a 256 x 16 strip (helder.image's Image)
//   post.lut = Lut.of(device, 16, (r, g, b) -> new Vec3(...));   // a grade of the program's own
//   post.lut.strength = 0.5;                                 // halfway from none to the table
class Lut implements PostPass {
	public final device:Device;
	// the table's size a side (16, 32)
	public final size:Int;
	// how much of it (0: none, 1: the table's)
	public var strength = 1.0;
	// the strip (RGBA8, size * size by size)
	public final texture:Texture;

	function new(device:Device, size:Int, pixels:Bytes) {
		PostFx.install();
		this.device = device;
		this.size = size;
		texture = device.createTexture({width: size * size, height: size, data: pixels});
	}

	// a strip's image (size * size by size: 256 x 16, 1024 x 32), its pixels RGBA8
	public static function fromImage(device:Device, image:helder.image.Image):Lut {
		var size = image.height;
		if (image.width != size * size) throw 'helder.scene: Lut.fromImage: a strip is size^2 x size (256 x 16, 1024 x 32), not ${image.width} x ${image.height}';
		return new Lut(device, size, image.pixels);
	}

	// a strip's RGBA8 texels (size * size by size: strip's), size a side
	public static function fromBytes(device:Device, size:Int, bytes:Bytes):Lut {
		if (bytes.length != size * size * size * 4) throw 'helder.scene: Lut.fromBytes: a $size cubed strip is ${size * size * size * 4} bytes, not ${bytes.length}';
		return new Lut(device, size, bytes);
	}

	// a table made from a grade (display values 0..1 in, out), size a side
	// (not TypeScript's yet: a Vec3 a TypeScript function returns does not
	// cross into Haxe; there helder/scene's lutStrip and fromBytes)
	@:noCompletion public static function of(device:Device, size:Int, grade:(r:Float, g:Float, b:Float) -> Vec3):Lut
		return new Lut(device, size, strip(size, grade));

	// the identity table (what a strip to grade in an editor starts from)
	public static function identity(device:Device, size = 16):Lut
		return of(device, size, (r, g, b) -> new Vec3(r, g, b));

	// a grade's strip, RGBA8 (a PNG of it is a strip to grade elsewhere;
	// TypeScript's: lutStrip, as of's)
	@:noCompletion public static function strip(size:Int, grade:(r:Float, g:Float, b:Float) -> Vec3):Bytes {
		var w = size * size, bytes = Bytes.alloc(w * size * 4), k = size - 1;
		for (y in 0...size)
			for (x in 0...w) {
				var c = grade((x % size) / k, y / k, Std.int(x / size) / k);
				var o = (y * w + x) * 4;
				bytes.set(o, Std.int(Math.max(0, Math.min(1, c.x)) * 255 + 0.5));
				bytes.set(o + 1, Std.int(Math.max(0, Math.min(1, c.y)) * 255 + 0.5));
				bytes.set(o + 2, Std.int(Math.max(0, Math.min(1, c.z)) * 255 + 0.5));
				bytes.set(o + 3, 255);
			}
		return bytes;
	}

	@:noCompletion public function require(fx:PostFx, renderer:Renderer) {}

	@:noCompletion public function draw(enc:Encoder, fx:PostFx):Int
		return 0;

	@:noCompletion public function result():Null<Texture>
		return null;

	// (its part of the composite's block: its size, its strength)
	@:noCompletion public function write(fx:PostFx)
		fx.block.lut = new Vec4(size, strength, 0, 0);

	@:noCompletion public function bind(enc:Encoder, fx:PostFx, slots:Array<Int>)
		if (slots[4] >= 0) enc.setTexture(slots[4], texture, fx.linear);

	public function dispose()
		device.destroyTexture(texture);
}
