package helder.gfx;

// Work the render thread does between the commands the devices hand it
// (Device.addIdle): helder.ui's compositor, whose frames go on while the
// program is busy. due and idle run on the render thread.
@:noCompletion
interface RenderIdle {
	// when it next runs (haxe.Timer.stamp's seconds; < 0: once woken, Device.wake)
	function due():Float;
	// its turn, with its device's back end (its commands run through r)
	function idle(r:Replay):Void;
}
