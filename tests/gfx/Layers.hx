import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import LayersShader;

// The layers frame (LayersShader): cube and 2D array textures. A cube of 2x2
// faces uploaded (each its colour of FACES, its last texel white), a cube
// drawn into (each face cleared to its colour halved, the first's bottom
// right quarter a white quad), a 2D array of two layers uploaded and one of two
// drawn (cleared), each read in a tile: check knows each tile's colours
class Layers {
	public static final FACES:Array<Array<Float>> = [[0, 1, 1], [1, 0, 0], [0, 1, 0], [1, 0, 1], [0, 0, 1], [1, 1, 0]];
	public static final LAYERS:Array<Array<Float>> = [[1, 0.5, 0], [0.25, 0.25, 0.25]];
	public static final DRAWN_LAYERS:Array<Array<Float>> = [[0, 0.5, 1], [0.5, 0, 1]];

	final quad:Buffer;
	final mark:Buffer;
	final pipeline:Pipeline;
	final marking:Pipeline;
	final faces:Texture;
	final drawn:Texture;
	final layers:Texture;
	final drawnLayers:Texture;
	final sampler:Sampler;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0)}]};
	final into:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0)}]};

	public function new(device:Device) {
		var full = LayersShader.vertexBytes([for (p in [[-1, -1], [1, -1], [1, 1], [-1, -1], [1, 1], [-1, 1]]) ({pos: new Vec2(p[0], p[1])} : LayersVertex)]);
		quad = device.createBuffer({size: full.length, usage: Vertex, data: full});
		// (the bottom right quarter: clip space y up)
		var q = MarkShader.vertexBytes([for (p in [[0, -1], [1, -1], [1, 0], [0, -1], [1, 0], [0, 0]]) ({pos: new Vec2(p[0], p[1])} : LayersVertex)]);
		mark = device.createBuffer({size: q.length, usage: Vertex, data: q});
		pipeline = device.createPipeline(LayersShader.pipeline());
		var d = MarkShader.pipeline();
		d.colorFormat = RGBA8;
		marking = device.createPipeline(d);
		var data = Bytes.alloc(6 * 4 * 4);
		for (f in 0...6)
			for (t in 0...4) {
				var c = t == 3 ? [1.0, 1.0, 1.0] : FACES[f];
				for (k in 0...3)
					data.set((f * 4 + t) * 4 + k, Math.round(c[k] * 255));
				data.set((f * 4 + t) * 4 + 3, 255);
			}
		faces = device.createTexture({width: 2, height: 2, cube: true, data: data});
		var l = Bytes.alloc(2 * 4 * 4);
		for (k in 0...2)
			for (t in 0...4)
				for (c in 0...4)
					l.set((k * 4 + t) * 4 + c, c == 3 ? 255 : Math.round(LAYERS[k][c] * 255));
		layers = device.createTexture({width: 2, height: 2, layers: 2});
		// (a layer at a time)
		device.writeTexture(layers, l, 0, 0, -1, -1, 0, 0, 0);
		device.writeTexture(layers, l, 0, 0, -1, -1, 16, 0, 1);
		drawn = device.createTexture({width: 8, height: 8, cube: true, renderTarget: true});
		drawnLayers = device.createTexture({width: 4, height: 4, layers: 2, renderTarget: true});
		sampler = device.createSampler({filter: Nearest, wrap: Clamp});
	}

	public function draw(enc:Encoder) {
		// (the drawn cube's faces and the drawn array's layers, then the screen)
		var c = into.colors[0];
		c.texture = drawn;
		for (f in 0...6) {
			c.layer = f;
			c.clear = new Color(FACES[f][0] * 0.5, FACES[f][1] * 0.5, FACES[f][2] * 0.5);
			enc.beginPass(into);
			if (f == 0) {
				enc.setPipeline(marking);
				enc.setVertexBuffer(0, mark);
				enc.draw(6);
			}
			enc.endPass();
		}
		c.texture = drawnLayers;
		for (k in 0...2) {
			c.layer = k;
			c.clear = new Color(DRAWN_LAYERS[k][0], DRAWN_LAYERS[k][1], DRAWN_LAYERS[k][2]);
			enc.beginPass(into);
			enc.endPass();
		}
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setTexture(LayersShader.params.faces.binding, faces, sampler);
		enc.setTexture(LayersShader.params.drawn.binding, drawn, sampler);
		enc.setTexture(LayersShader.params.layers.binding, layers, sampler);
		enc.setTexture(LayersShader.params.drawnLayers.binding, drawnLayers, sampler);
		enc.setVertexBuffer(0, quad);
		enc.draw(6);
		enc.endPass();
	}

	// each tile's colours (a cube's face: its bottom right quarter white, the
	// rest its colour; an array's layer: its colour) at their middles: null,
	// or what differs
	public static function check(pixels:Bytes, width:Int, height:Int):Null<String> {
		var wrong = [];
		function at(x:Float, y:Float, want:Array<Float>, what:String) {
			var p = 4 * (Std.int(y) * width + Std.int(x));
			for (c in 0...3)
				if (Math.abs(pixels.get(p + c) - Math.round(want[c] * 255)) > 2) {
					wrong.push(what + ": " + [for (k in 0...3) pixels.get(p + k)] + ", not " + [for (k in 0...3) Math.round(want[k] * 255)]);
					return;
				}
		}
		var tw = width / 6, th = height / 3;
		for (f in 0...6) {
			at((f + 0.75) * tw, 0.75 * th, [1, 1, 1], "face " + f + ", its last texel");
			at((f + 0.25) * tw, 0.25 * th, FACES[f], "face " + f);
			at((f + 0.75) * tw, 1.75 * th, f == 0 ? [1, 1, 1] : [for (c in FACES[f]) c * 0.5], "drawn face " + f + ", its bottom right");
			at((f + 0.25) * tw, 1.25 * th, [for (c in FACES[f]) c * 0.5], "drawn face " + f);
		}
		for (k in 0...4)
			at((k + 0.5) * width / 4, 2.5 * th, k < 2 ? LAYERS[k] : DRAWN_LAYERS[k - 2], "layer " + k);
		return wrong.length == 0 ? null : wrong.join("; ");
	}
}
