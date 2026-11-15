// title: Picking
// summary: Paint on a model: a <Scene pick="triangles"> gives each press and drag the triangle under the pointer, its uv where the brush lands in the model's texture and its normal for the cursor's ring
// tags: 3d, picking, raycast, scene markup
// demo: canvas 640x400
import haxe.io.Bytes;
import helder.gfx.Texture;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.render.Geometry;
import helder.scene.render.Light;
import helder.scene.render.Lines;
import helder.scene.render.Material;
import helder.scene.render.Renderer;
import helder.scene.view.SceneEvent;
import helder.scene.view.SceneTags.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

// Painting on a model (src/helder/scene/README.md, "Picking"):
//
// - <Scene pick="triangles"> picks by the meshes' triangles (each
//   primitive's tree made when first picked at), not their bounds, so a
//   SceneEvent knows the triangle under the pointer: its point, its
//   normal and its uv. A drag that stays on the model keeps them coming.
// - The brush writes a disc into the model's texture at the uv (the
//   texture's bytes, written to the GPU once a stroke's step is done).
// - The cursor is Lines: a ring at the point, turned to the normal.
// - Turn the model with the buttons; Clear starts again.
//
// The raycast itself is world.raycast(origin, dir, hit), which a program
// can call anywhere: a click through Camera.ray, a line of sight.
class Picking implements Markup {
	// (the canvas: as long round the knot as its tube's way round it, 8 to 1)
	static inline var W = 1024;
	static inline var H = 128;

	static function main() {
		var world = new World("picking"), eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 50));
		eye.position = new Vec3(0, 0.3, 4.2);
		eye.lookAt(new Vec3(0, 0, 0));
		var sun = world.node("sun");
		sun.rotation = Quat.fromEuler(-0.7, 0.5, 0);
		Light.attach(sun, Light.directional(new Vec3(1, 0.97, 0.92), 1.8));
		var angle = 0.6, colour = signal(0), hint = signal("Press and drag on the knot");
		var turn = signal(Quat.fromEuler(0.3, angle, 0));
		function turnBy(a:Float) {
			angle += a;
			turn(Quat.fromEuler(0.3, angle, 0));
		}
		// (a stroke: from a press on the knot to its release)
		var painting = false;
		// (the canvas: cream; its texture made on the box's device)
		var pixels = Bytes.alloc(W * H * 4);
		var texture:Null<Texture> = null, device:Null<helder.gfx.Device> = null;
		function clear() {
			for (i in 0...W * H)
				pixels.setInt32(i * 4, 0xFFD8E8F0);
			if (texture != null) device.writeTexture(texture, pixels);
		}
		clear();
		var paint = Material.lambert({color: new Vec4(1, 1, 1, 1)});
		var knot = Geometry.torusKnot({radius: 0.8, tube: 0.3, tubularSegments: 160, radialSegments: 16});
		function setup(r:Renderer) {
			device = r.device;
			texture = device.createTexture({width: W, height: H, format: RGBA8Srgb, data: pixels});
			paint.baseColorTexture = texture;
		}
		// (a ring of 32 points, round the cursor)
		var cursor = new Lines(32, {width: 3, closed: true, onTop: true, toneMapped: false});
		function place(e:SceneEvent) {
			var n = e.normal, p = e.point + e.normal * 0.01;
			var a = Math.abs(n.x) < 0.9 ? new Vec3(1, 0, 0) : new Vec3(0, 1, 0);
			var u = cross(n, a), l = Math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z);
			u = u / l;
			var v = cross(n, u);
			cursor.count = 32;
			for (k in 0...32) {
				var t = k / 32 * Math.PI * 2, q = p + (u * Math.cos(t) + v * Math.sin(t)) * 0.08;
				cursor.setPoint(k, q.x, q.y, q.z, 1, 0.85, 0.2);
			}
		}
		function brush(e:SceneEvent) {
			var c = COLOURS[colour()];
			var cx = e.uv.x * W, cy = e.uv.y * H, r = 5;
			for (dy in -r...r + 1)
				for (dx in -r...r + 1)
					if (dx * dx + dy * dy <= r * r) {
						// (the texture repeats: the tube's seam paints across)
						var x = (Std.int(cx) + dx + W) % W, y = (Std.int(cy) + dy + H) % H;
						pixels.setInt32((y * W + x) * 4, c);
					}
			if (texture != null) device.writeTexture(texture, pixels);
			hint('uv ${Math.round(e.uv.x * 100) / 100}, ${Math.round(e.uv.y * 100) / 100}');
		}
		UiWindow.run(<Surface title="Picking" width={640} height={400}>
			<view direction="row" grow={1}>
				<Scene world={world} camera={camera} grow={1} pick="triangles" setup={setup}>
					<mesh name="knot" geometry={knot} material={paint} rotation={turn} onPointerDown={e -> {
						painting = true;
						brush(e);
						place(e);
					}} onPointerMove={e -> {
						place(e);
						if (painting) brush(e);
					}} onPointerUp={_ -> painting = false} onPointerCancel={_ -> painting = false} onPointerLeave={_ -> cursor.count = 0}/>
					<lines of={cursor}/>
				</Scene>
				<view width={170} padding={14} row-gap={8} background="#18181b" color="#fafafa" font-size={13}>
					<text font-size={15}>Paint</text>
					<view direction="row" column-gap={6}>
						<Swatch k={0} colour={colour}/>
						<Swatch k={1} colour={colour}/>
						<Swatch k={2} colour={colour}/>
						<Swatch k={3} colour={colour}/>
					</view>
					<view direction="row" column-gap={6}>
						<Button label="Turn left" press={() -> turnBy(-0.6)}/>
						<Button label="Turn right" press={() -> turnBy(0.6)}/>
					</view>
					<Button label="Clear" press={clear}/>
					<text color="#a1a1aa">{hint}</text>
				</view>
			</view>
		</Surface>);
	}

	// (the brush's colours, as the texture's bytes: ABGR)
	static final COLOURS = [0xFF2040E0, 0xFF30B040, 0xFFE07020, 0xFF202020];
	static final CSS = ["#e04020", "#40b030", "#2070e0", "#202020"];

	static function Swatch(props:{k:Int, colour:helder.view.graph.Signal<Int>}):View
		return <view width={props.colour() == props.k ? 30 : 22} height={props.colour() == props.k ? 30 : 22} radius={15} background={CSS[props.k]}
			onPress={() -> props.colour(props.k)}/>;

	static function Button(props:{label:String, press:Void->Void}):View
		return <view padding="5 8" radius={4} background="#27272a" onPress={props.press}><text>{props.label}</text></view>;

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
