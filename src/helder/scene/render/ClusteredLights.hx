package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.math.Mat4;
import helder.math.Vec4;
import helder.scene.render.ClusterShader;

// Clustered lighting (Forward+), opted in for scenes of many lights
// (renderer.use(new ClusteredLights(device, {maxLights: 256}))): the view
// cut into a grid of cells (Clusters: grid.x by grid.y tiles, grid.z slices
// of depth growing away from the camera), each cell listing the frame's
// lights that reach it (at most maxPerCell), and each pixel lit by its
// cell's lights instead of its draw's eight. The lists and the frame's
// lights (up to maxLights, the renderer's FrameLights: the most important
// to the view) go into one texture, the cluster map (R32F: each cell its
// count then its lights' rows, then a row a light), read by pbr's light
// loop where frame.clusters.x is on: no variant of any material more, no
// uniform block past GL ES 3.0's 16 KB or Metal's 4 KB (the renderer's 32 rows
// stay the draws'), one texture more (a pipeline's slots are 16), so it
// runs on WebGL2.
//
// Where the device has compute (Device.has(Compute)) the cells are
// assigned on the GPU (ClusterShader: a dispatch a frame, an invocation a
// cell, the lights copied in from a storage buffer), else on the CPU
// (Clusters.assign, then the map uploaded): the
// same test in the same order, so the same lists. Shadowed local lights
// take part with their tiles (Shadows). The camera is perspective. Nothing
// is allocated a frame.
class ClusteredLights implements RenderFeature implements RenderFeature.ClusterSource {
	public final device:Device;
	// the frame's lights it lights with at most
	public final maxLights:Int;
	// whether its cells are assigned on the GPU (the device has compute and
	// gpu was not turned off), else on the CPU
	public final gpu:Bool;
	// the grid and its lists (the CPU's assignment, the map's layout)
	public final clusters:Clusters;
	// the last frame's lights, its full cells' lights left out (the CPU's only)
	public var lights(default, null) = 0;
	public var overflow(default, null) = 0;
	// the CPU's last assignment, in ms (the GPU's: 0)
	public var assignMs(default, null) = 0.0;

	final clusterMap:Texture;
	// (the compute path's: the lights' vectors, FrameLights' data)
	var lightBuffer:Buffer = Buffer.NONE;
	final rows:Bytes;
	final frame = new RenderFeature.ClusterFrame();
	final xs:Array<Float>;
	final ys:Array<Float>;
	final zs:Array<Float>;
	final rs:Array<Float>;
	var pipeline:Null<ComputePipeline> = null;
	final gridBytes = Bytes.alloc(ClusterAssign.params.grid.block.size);
	final gridBlock:ClusterGrid = {view: Mat4.identity(), lens: new Vec4(0, 0, 0, 0), tilesX: 0, tilesY: 0, slices: 0, perCell: 0, lights: 0, rows: 0, lightRow: 0};

	// options: maxLights (256), grid ({x: 16, y: 9, z: 24}), maxPerCell (32),
	// gpu (true: on the GPU where the device can)
	public function new(device:Device, ?options:ClusteredOptions) {
		this.device = device;
		maxLights = options != null && options.maxLights != null ? options.maxLights : 256;
		var g = options != null ? options.grid : null;
		clusters = new Clusters(g != null && g.x != null ? g.x : 16, g != null && g.y != null ? g.y : 9, g != null && g.z != null ? g.z : 24,
			options != null && options.maxPerCell != null ? options.maxPerCell : 32, maxLights);
		gpu = (options == null || options.gpu != false) && device.has(Compute) && device.has(StorageTextures);
		rows = Bytes.alloc(maxLights * FrameLights.FLOATS * 4);
		clusterMap = device.createTexture({width: clusters.width, height: clusters.height, format: R32F, storage: gpu});
		if (gpu) {
			pipeline = device.createComputePipeline(ClusterAssign.pipeline());
			lightBuffer = device.createBuffer({size: rows.length, usage: Storage});
		}
		xs = Filled.floats(maxLights, 0.0);
		ys = Filled.floats(maxLights, 0.0);
		zs = Filled.floats(maxLights, 0.0);
		rs = Filled.floats(maxLights, 0.0);
		frame.clusterMap = clusterMap;
	}

	public function attach(renderer:Renderer)
		@:privateAccess renderer.clusterSource = this;

	@:noCompletion public function capacity():Int
		return maxLights;

	@:noCompletion public function clusterFrame():RenderFeature.ClusterFrame
		return frame;

	@:noCompletion public function assign(enc:Encoder, renderer:Renderer, view:Renderer.FrameInfo) {
		var l = renderer.frameLights, cam = view.camera;
		lights = l.count < maxLights ? l.count : maxLights;
		var near = cam != null ? cam.near : 0.1, far = cam != null ? cam.far : 100.0;
		clusters.lens(view.projection, near, far);
		var c = clusters;
		frame.clusters = new Vec4(c.tilesX, c.tilesY, c.slices, c.perCell);
		frame.depth = new Vec4(near, 1 / c.step, c.width, c.height);
		var fwd = view.view;
		// (the camera's forward: the view's third row, negated)
		frame.axis = new Vec4(-fwd.c0.z, -fwd.c1.z, -fwd.c2.z, c.lightRow);
		if (gpu) {
			var g = gridBlock;
			g.view = view.view;
			g.lens = new Vec4(c.slopeX, c.slopeY, near, c.step);
			g.tilesX = c.tilesX;
			g.tilesY = c.tilesY;
			g.slices = c.slices;
			g.perCell = c.perCell;
			g.lights = lights;
			g.rows = maxLights;
			g.lightRow = c.lightRow;
			ClusterAssign.params.grid.write(g, gridBytes);
			// (the lights' vectors, their tiles set by Shadows before: copied into the map by the dispatch)
			l.writeRows(rows, maxLights);
			device.writeBuffer(lightBuffer, 0, rows);
			enc.beginCompute();
			enc.setComputePipeline(pipeline);
			enc.setUniforms(ClusterAssign.params.grid.block.binding, gridBytes);
			enc.setStorage(ClusterAssign.params.lights.binding, lightBuffer);
			enc.setStorageTexture(ClusterAssign.params.clusterMap.binding, clusterMap);
			enc.dispatch(ClusterAssign.groups(c.tilesX * c.tilesY * c.slices + maxLights * 3));
			enc.endCompute();
			assignMs = 0;
			return;
		}
		var t0 = haxe.Timer.stamp();
		for (k in 0...lights) {
			xs[k] = l.x(k);
			ys[k] = l.y(k);
			zs[k] = l.z(k);
			rs[k] = l.range(k);
		}
		c.assign(view.view, xs, ys, zs, rs, lights);
		c.writeLights(l);
		overflow = c.overflow;
		device.writeTexture(clusterMap, c.map);
		assignMs = (haxe.Timer.stamp() - t0) * 1000;
	}

	public function dispose() {
		device.destroyTexture(clusterMap);
		if (gpu) device.destroyBuffer(lightBuffer);
	}
}

// ClusteredLights' options (new ClusteredLights(device, options))
typedef ClusteredOptions = {
	// the frame's lights it takes at most (256)
	?maxLights:Int,
	// the grid: tiles across and down the view, slices of depth (16, 9, 24)
	?grid:{?x:Int, ?y:Int, ?z:Int},
	// a cell's lights at most (32)
	?maxPerCell:Int,
	// false: on the CPU even where the device has compute
	?gpu:Bool
}
