import helder.math.*;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import FlockShaders;

// The birds and their step: on a device with compute three dispatches a
// step over two buffers taken in turn (the one stepped from, the one
// stepped into, which the frame then draws as instances). Without compute
// the same stages run on the CPU over fewer birds, uploaded each frame.
// The first `live` birds fly: a GPU starts with an eighth of them, doubled
// (Spread) while it keeps up, halved when it does not.
class Flock {
	public static inline var GPU_BIRDS = 524288;
	public static inline var CPU_BIRDS = 6144;
	static inline var GPU_CELLS = 262144;
	static inline var CPU_CELLS = 8192;

	public final count:Int;
	public final compute:Bool;
	public final step:FlockStep;
	public var live(default, null):Int;
	// (the most that fly: a page asks for fewer on a phone's GPU)
	public var limit:Int;
	final device:Device;
	final birds:Array<Buffer> = [];
	final stepBytes = Bytes.alloc(Steer.params.step.block.size);
	var random = 7;
	var nextWave = 0.0;
	var startedWave = 0.0;
	var waveAxis = new Vec3(0, 0, 0);
	var waveStart = 0.0;
	var turn = 0;
	var doubling = false;
	// (the GPU's grid and stages)
	var counts:Null<Buffer>;
	var mates:Null<Buffer>;
	var clear:Null<ComputePipeline>;
	var insert:Null<ComputePipeline>;
	var steer:Null<ComputePipeline>;
	var spread:Null<ComputePipeline>;
	// (the CPU's: the birds stepped from and into, the grid, the ids)
	var from:Array<Bird> = [];
	var into:Array<Bird> = [];
	var cpuCounts:Array<Int> = [];
	var cpuMates:Array<Mate> = [];
	var cpuBytes:Null<Bytes>;
	final id = ComputeInput.at(0, 0, 0, 64, 1, 1);

	public function new(device:Device, roost:Vec3, heading:Vec3, all = false) {
		this.device = device;
		compute = device.has(Compute);
		count = compute ? GPU_BIRDS : CPU_BIRDS;
		live = compute && !all ? count >> 3 : count;
		limit = count;
		var cells = compute ? GPU_CELLS : CPU_CELLS;
		step = {dt: 0, time: 0, count: live, cells: cells, roost: new Vec4(roost.x, roost.y, roost.z, 40), heading: new Vec4(0, 0, 0, 1),
			armA: new Vec4(0, 0, 0, 0), armB: new Vec4(0, 0, 0, 0), hawk: new Vec4(0, -1000, 0, 0), hawkVel: new Vec4(1, 0, 0, 0),
			wave: new Vec4(0, 0, 0, -1)};
		// (a ball about the roost, already on the wing its way)
		var r0 = 40 * Math.pow(live / GPU_BIRDS, 1 / 3);
		for (i in 0...count) {
			var a = rand() * Math.PI * 2, r = Math.sqrt(rand()) * r0, y = (rand() - 0.5) * r0 * 0.5;
			from.push({
				pos: new Vec4(roost.x + Math.cos(a) * r, roost.y + y, roost.z + Math.sin(a) * r, rand() * 6.28),
				vel: new Vec4(heading.x + rand() - 0.5, heading.y + rand() - 0.5, heading.z + rand() - 0.5, 0),
				mood: new Vec4(0, 0.5, 0, 0)
			});
		}
		nextWave = 1.5 + 1.5 * rand();
		var initial = Steer.params.next.bytesOf(from);
		for (_ in 0...2)
			birds.push(device.createBuffer({size: initial.length, usage: compute ? Storage : Vertex, data: initial}));
		if (compute) {
			from = [];
			counts = device.createBuffer({size: 4 * cells, usage: Storage});
			mates = device.createBuffer({size: Steer.params.mates.stride * cells * SLOTS, usage: Storage});
			clear = device.createComputePipeline(Clear.pipeline());
			insert = device.createComputePipeline(Insert.pipeline());
			steer = device.createComputePipeline(Steer.pipeline());
			spread = device.createComputePipeline(Spread.pipeline());
		} else {
			into = from.copy();
			cpuCounts = [for (_ in 0...cells) 0];
			cpuMates = [for (_ in 0...cells * SLOTS) {pos: new Vec4(0, 0, 0, 0), vel: new Vec4(0, 0, 0, 0)}];
			cpuBytes = initial;
		}
	}

	function rand():Float {
		random = (random * 1103515245 + 12345) & 0x7fffffff;
		return random / 0x7fffffff;
	}

	// the birds as the last step left them: the frame's instances
	public function current():Buffer
		return birds[turn];

	// twice as many birds from the next step (false: all of them already)
	public function grow():Bool {
		if (!compute || doubling || live >= count || live * 2 > limit) return false;
		doubling = true;
		return true;
	}

	public function shrink():Bool {
		if (live <= count >> 5) return false;
		live >>= 1;
		return true;
	}

	// a step of dt seconds (recorded before the frame's passes)
	public function advance(enc:Encoder, dt:Float, time:Float) {
		step.dt = dt;
		step.time = time;
		waveAt(time);
		if (!compute) return cpu();
		var src = birds[turn], dst = birds[1 - turn];
		turn = 1 - turn;
		enc.beginCompute();
		if (doubling) {
			step.count = live;
			Spread.params.step.write(step, stepBytes);
			enc.setComputePipeline(spread);
			enc.setUniforms(Spread.params.step.block.binding, stepBytes);
			enc.setStorage(Spread.params.birds.binding, src);
			enc.dispatch(Spread.groups(live));
			live <<= 1;
			doubling = false;
		}
		step.count = live;
		Steer.params.step.write(step, stepBytes);
		enc.setComputePipeline(clear);
		enc.setUniforms(Clear.params.step.block.binding, stepBytes);
		enc.setStorage(Clear.params.counts.binding, counts);
		enc.dispatch(Clear.groups(step.cells));
		enc.setComputePipeline(insert);
		enc.setUniforms(Insert.params.step.block.binding, stepBytes);
		enc.setStorage(Insert.params.birds.binding, src);
		enc.setStorage(Insert.params.counts.binding, counts);
		enc.setStorage(Insert.params.mates.binding, mates);
		enc.dispatch(Insert.groups(live));
		enc.setComputePipeline(steer);
		enc.setUniforms(Steer.params.step.block.binding, stepBytes);
		enc.setStorage(Steer.params.birds.binding, src);
		enc.setStorage(Steer.params.counts.binding, counts);
		enc.setStorage(Steer.params.mates.binding, mates);
		enc.setStorage(Steer.params.next.binding, dst);
		enc.dispatch(Steer.groups(live));
		enc.endCompute();
	}

	function waveAt(time:Float) {
		if (time >= nextWave) {
			startedWave = time;
			nextWave = time + 1.5 + 1.5 * rand();
			var angle = rand() * Math.PI * 2;
			var axis = new Vec3(Math.cos(angle), 1.6 * (rand() - 0.5), Math.sin(angle));
			var toHawk = step.hawk.xyz - step.roost.xyz;
			if (step.hawk.w > 8 && dot(toHawk, toHawk) > 1) axis = -toHawk;
			var dir = normalize(axis);
			// The projected arms and radius keep the band proportional as the flock stretches.
			var a = dot(dir, step.armA.xyz), b = dot(dir, step.armB.xyz);
			var pad = step.roost.w * 1.15;
			var near = Math.min(0, Math.min(a, b)) - pad, far = Math.max(0, Math.max(a, b)) + pad;
			var extent = far - near;
			waveAxis = dir / extent;
			waveStart = near / extent - 0.06;
		}
		if (startedWave == 0) return;
		var progress = (time - startedWave) / (nextWave - startedWave);
		step.wave = new Vec4(waveAxis.x, waveAxis.y, waveAxis.z, waveStart + progress * 1.31);
	}

	function cpu() {
		step.count = live;
		// (only the cells the birds were filed in last time emptied: Clear's work, cheaper)
		for (k in 0...live)
			cpuCounts[cellOf(into[k].pos.xyz, step.cells)] = 0;
		var filing = {step: step, birds: (from : Storage<Bird>), counts: (cpuCounts : RWStorage<Int>), mates: (cpuMates : RWStorage<Mate>)};
		for (i in 0...live) {
			id.x = i;
			Insert.main(id, filing);
		}
		var steering = {step: step, birds: (from : Storage<Bird>), counts: (cpuCounts : Storage<Int>), mates: (cpuMates : Storage<Mate>),
			next: (into : RWStorage<Bird>)};
		for (i in 0...live) {
			id.x = i;
			Steer.main(id, steering);
		}
		var t = from;
		from = into;
		into = t;
	}

	public function upload() {
		Steer.params.next.store(from, cpuBytes);
		device.writeBuffer(birds[turn], 0, cpuBytes);
	}
}
