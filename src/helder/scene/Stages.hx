package helder.scene;

// A frame's work in ordered stages, on top of helder.os.App's frames:
//
//   Input        once a frame, first (read devices, feed InputMap)
//   FixedUpdate  at the fixed rate, as many times as the frame holds
//                (FixedStep: physics, gameplay), with the step's dt
//   Update       once a frame, with the frame's seconds
//   LateUpdate   once a frame, after Update (cameras following things)
//   PreRender    once a frame, last, with FixedStep's alpha (interpolation)
//
// Within a stage, functions run in the order they were added; on returns a
// function that removes one (a component's cleanup).
//
//   var stages = new Stages();
//   stages.on(FixedUpdate, dt -> physics.step(dt));
//   stages.on(LateUpdate, _ -> follow(camera, player));
//   App.run(() -> { stages.frame(seconds); renderer.draw(...); }, ...);
class Stages {
	public final clock:FixedStep;
	// (each stage's functions, iterated in place: one removed is nulled in
	// its entry, the list compacted after its stage has run or once half of
	// it is holes; one added runs from the next frame)
	final lists:Array<Array<StageEntry>> = [for (_ in 0...5) []];
	final holes:Array<Int> = [for (_ in 0...5) 0];
	final running:Array<Bool> = [for (_ in 0...5) false];
	// (FixedUpdate's step, made once: no closure a frame)
	final fixedStep:Float->Void;

	public function new(?clock:FixedStep) {
		this.clock = clock != null ? clock : new FixedStep();
		fixedStep = dt -> run(FixedUpdate, dt);
	}

	public function on(stage:Stage, f:Float->Void):Void->Void {
		var e = new StageEntry(f);
		lists[stage].push(e);
		return () -> {
			if (e.f == null) return;
			e.f = null;
			holes[stage]++;
			if (!running[stage] && holes[stage] * 2 > lists[stage].length) compact(stage);
		};
	}

	// one frame of seconds
	public function frame(seconds:Float) {
		// (loads in flight advanced first: helder.asset's Asset)
		helder.asset.Assets.poll();
		// (gamepads read once a frame, before the Input stage, when the program
		// enabled them: InputMap see them)
		helder.os.Gamepads.poll();
		run(Input, seconds);
		clock.advance(seconds, fixedStep);
		run(Update, seconds);
		run(LateUpdate, seconds);
		run(PreRender, clock.alpha);
	}

	function run(stage:Stage, v:Float) {
		var list = lists[stage], n = list.length;
		if (n == 0) return;
		running[stage] = true;
		for (k in 0...n) {
			var f = list[k].f;
			if (f != null) f(v);
		}
		running[stage] = false;
		if (holes[stage] > 0) compact(stage);
	}

	function compact(stage:Stage) {
		var list = lists[stage], w = 0;
		for (k in 0...list.length)
			if (list[k].f != null) list[w++] = list[k];
		list.resize(w);
		holes[stage] = 0;
	}
}

// (a stage's function, nulled when removed)
private class StageEntry {
	public var f:Null<Float->Void>;

	public function new(f:Float->Void)
		this.f = f;
}

enum abstract Stage(Int) to Int {
	var Input;
	var FixedUpdate;
	var Update;
	var LateUpdate;
	var PreRender;
}
