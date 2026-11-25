package helder.async;

// A headless run's virtual clock (helder.os.headless.Headless): the seconds
// since the run began, as the loop has stepped them (each frame 1/fps
// later; an event's own time while it is handled). What reads the time in
// a build for a headless run (-D helder.headless: App's frames, ui's Clock
// and events, helder.async's timers) reads this instead of
// haxe.Timer.stamp(), so a run is the same whatever the machine's speed:
// `#if helder.headless helder.async.Time.now #else haxe.Timer.stamp()
// #end`. It is helder.async's, below what reads it, and imports nothing.
class Time {
	public static var now = 0.0;
}
