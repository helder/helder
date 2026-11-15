package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec4;
import helder.scene.render.PostEffects;

// Outline's part of the composite (PostFx's, made by post.outline's
// setter's factory): the view buffers asked for whole, its block's part,
// the groups' texture (256 x 2 RGBA8: colours, then widths over 255),
// written when a group changed. A module of its own: an Outline made and
// never set on a chain links none of it.
class OutlinePass implements PostPass {
	final outline:Outline;
	var texture:Null<Texture> = null;
	var device:Null<Device> = null;
	final bytes = Bytes.alloc(256 * 2 * 4);

	public function new(outline:Outline)
		this.outline = outline;

	public static function make(outline:Outline):PostPass
		return new OutlinePass(outline);

	@:noCompletion public function require(fx:PostFx, renderer:Renderer)
		fx.read(ViewBuffers.of(renderer), 1);

	@:noCompletion public function draw(enc:Encoder, fx:PostFx):Int
		return 0;

	@:noCompletion public function result():Null<Texture>
		return null;

	// (its part of the composite's block: on, the widest group, a pixel of the target)
	@:noCompletion public function write(fx:PostFx)
		fx.block.outline = new Vec4(1, outline.widest(), 1 / Math.max(1, fx.post.width), 1 / Math.max(1, fx.post.height));

	@:noCompletion public function bind(enc:Encoder, fx:PostFx, slots:Array<Int>)
		if (slots[5] >= 0) enc.setTexture(slots[5], groupsTexture(fx.device), fx.nearest);

	// (the groups' colours in the first row, widths over 255 in the second's red)
	function groupsTexture(d:Device):Texture {
		if (texture == null) {
			device = d;
			texture = d.createTexture({width: 256, height: 2});
		}
		if (outline.changed) {
			for (k in 0...256) {
				var c = @:privateAccess outline.colors[k];
				bytes.set(k * 4, Std.int(Math.max(0, Math.min(1, c.x)) * 255 + 0.5));
				bytes.set(k * 4 + 1, Std.int(Math.max(0, Math.min(1, c.y)) * 255 + 0.5));
				bytes.set(k * 4 + 2, Std.int(Math.max(0, Math.min(1, c.z)) * 255 + 0.5));
				bytes.set(k * 4 + 3, Std.int(Math.max(0, Math.min(1, c.w)) * 255 + 0.5));
				var o = (256 + k) * 4;
				bytes.set(o, Std.int(@:privateAccess outline.widths[k] + 0.5));
				bytes.set(o + 1, 0);
				bytes.set(o + 2, 0);
				bytes.set(o + 3, 255);
			}
			d.writeTexture(texture, bytes);
			outline.changed = false;
		}
		return texture;
	}

	@:noCompletion public function dispose() {
		if (texture != null) device.destroyTexture(texture);
		texture = null;
		outline.changed = true;
	}
}
