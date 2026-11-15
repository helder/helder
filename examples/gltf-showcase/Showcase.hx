import helder.gfx.Device;
import helder.gfx.shader.Vec3;
import helder.scene.*;
import helder.scene.math.Aabb;
import helder.scene.render.*;

using helder.scene.math.MathTools;

// The showcase's scene, the example's (GltfShowcase) and the reference
// frames' (Shots): Khronos' sample models (fetched by fetch.mjs into
// models/, each one .glb) lit by prefiltered environments
// (environments/*.png, baked by envbake.py from Poly Haven's CC0 panoramas),
// in HDR through ACES, the camera fitted to the model's bounds.
class Showcase {
	// the models: name, its credit (each one's <name>.json has the whole of it)
	public static final MODELS:Array<{name:String, credit:String}> = [
		{name: "DamagedHelmet", credit: "CC BY 4.0 ctxwing, after theblueturtle_ (CC BY-NC 4.0)"},
		{name: "FlightHelmet", credit: "CC0 Gary Hsu"},
		{name: "SciFiHelmet", credit: "CC0 Michael Pavlovic, Norbert Nopper"},
		{name: "MetalRoughSpheres", credit: "CC BY 4.0 Ed Mackey"},
		{name: "TextureTransformTest", credit: "CC0 Microsoft"},
		{name: "EmissiveStrengthTest", credit: "CC BY 4.0 Ed Mackey"},
		{name: "ClearCoatTest", credit: "CC BY 4.0 Ed Mackey"},
		{name: "TransmissionTest", credit: "CC0 Adobe"},
		{name: "SheenChair", credit: "CC0 Eric Chadwick"},
		{name: "IridescenceLamp", credit: "CC BY 4.0 Eric Chadwick"},
		{name: "AnisotropyBarnLamp", credit: "CC BY 4.0 Eric Chadwick"},
		{name: "IORTestGrid", credit: "CC0 Eric Chadwick"},
		{name: "SpecularTest", credit: "CC BY 4.0 Ed Mackey"},
		{name: "DragonAttenuation", credit: "Stanford Graphics, Morgan McGuire's archive; CC0 Adobe"},
		{name: "CompareSheen", credit: "CC0 Eric Chadwick and DGG"},
		{name: "CompareIridescence", credit: "CC0 Eric Chadwick and DGG"},
		{name: "CompareAnisotropy", credit: "CC0 Eric Chadwick and DGG"},
		{name: "CompareSpecular", credit: "CC0 Eric Chadwick and DGG"},
		{name: "CompareIor", credit: "CC0 Eric Chadwick and DGG"},
		{name: "CompareVolume", credit: "CC0 Eric Chadwick and DGG"},
		{name: "AttenuationTest", credit: "CC BY 4.0 Ed Mackey"},
		{name: "TransmissionRoughnessTest", credit: "CC BY 4.0 Ed Mackey"}
	];
	// the environments: file, label, intensity (envbake.py's scale)
	public static final ENVIRONMENTS:Array<{file:String, label:String, intensity:Float}> = [
		{file: "studio_small_09", label: "Studio", intensity: 6.055},
		{file: "venice_sunset", label: "Sunset", intensity: 2.214},
		{file: "kloofendal_48d_partly_cloudy_puresky", label: "Sky", intensity: 5.131}
	];

	public final world = new World("showcase");
	public final camera:Camera;
	public final eye:Node;
	public var environments:Array<Environment> = [];
	// the model shown, its root and bounds
	public var root = Node.NONE;
	public var bounds = Aabb.empty();
	// the file's first camera, if it has one
	public var fileCamera:Null<Camera>;

	public function new() {
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.8, 0.01, 100));
	}

	// #region environments
	// the renderer's features: normal maps, the glTF extensions of models
	// loaded at run time (Physical) with the frame behind see-through ones
	// (Transmission), the environments (the first shown; prefiltered by
	// helder at load from their atlases' first row, the panorama itself:
	// Environment.prefilter), bloom and ACES; envs: each environment's atlas bytes
	public function setup(r:Renderer, envs:Array<haxe.io.Bytes>) {
		r.clearColor = new helder.gfx.Color(0.05, 0.05, 0.06, 1);
		r.use(new NormalMaps(r.device));
		r.use(new Physical());
		r.use(new Transmission(r.device));
		environments = [];
		for (k in 0...envs.length) {
			var image = Images.decode == null ? null : Images.decode("image/png", envs[k]);
			if (image == null) continue;
			// (the first row: the sphere at roughness 0, width by width / 2)
			var w = image.width, h = w >> 1;
			var e = Environment.prefilter(r.device, w, h, image.rgba.sub(0, w * h * 4), helder.gfx.TextureFormat.RGBA8, {size: 128, levels: 6});
			e.intensity = ENVIRONMENTS[k].intensity;
			r.use(e);
			environments.push(e);
		}
		r.sunColor = new Vec3(0, 0, 0);
		r.exposure = 1;
		environment(r, 0);
	}
	// #endregion

	// the environment k lights and is drawn behind the scene
	public function environment(r:Renderer, k:Int) {
		for (i in 0...environments.length)
			environments[i].background = i == k;
		if (k < environments.length) @:privateAccess r.environment = environments[k];
	}

	// model in place of the one shown: its bounds measured
	public function show(model:Model<{}, {}, {}, {}>, device:Device) {
		if (!root.isNone) root.dispose();
		root = model.instantiate(world, device);
		bounds = Aabb.empty();
		var meshes = world.store(MeshRenderer.KIND);
		for (k in 0...meshes.length) {
			var n = meshes.nodeAt(k);
			if (world.inTree(n)) bounds = bounds.union(meshes.valueAt(k).bounds.transform(n.worldMatrix()));
		}
		fileCamera = null;
		var cameras = world.store(Camera.KIND);
		for (k in 0...cameras.length)
			if (cameras.nodeAt(k) != eye && world.inTree(cameras.nodeAt(k)) && fileCamera == null) fileCamera = cameras.valueAt(k);
	}

	// the model's centre and the distance that fits its bounds in the view
	public function centre():Vec3
		return bounds.isEmpty() ? new Vec3(0, 0, 0) : (bounds.min + bounds.max) * 0.5;

	// (the bounds' box seen from the front, along -z: its width and height
	// within the view at aspect, its depth's half in front)
	public function fitDistance(aspect = 1.0):Float {
		if (bounds.isEmpty()) return 3;
		var d = bounds.max - bounds.min, t = Math.tan(0.4);
		return Math.max(d.x * 0.5 / (t * aspect), d.y * 0.5 / t) * 1.1 + d.z * 0.5;
	}

	// the camera at yaw, pitch and the fitted distance about the centre
	public function look(yaw:Float, pitch:Float, aspect = 1.0) {
		var c = centre(), d = fitDistance(aspect);
		eye.position = c + new Vec3(Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), Math.cos(yaw) * Math.cos(pitch)) * d;
		eye.lookAt(c);
	}
}
