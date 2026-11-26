package helder.os;

// The wall clock a screen reads (ms since 1970): a scenario's start instant
// on its virtual clock (helder.ui.ScreenContext.epoch), else null: the
// system's. TypeScript's Date.now and new Date() read it; Haxe's Date.now
// does not yet
class Now {
	public static var get:Null<Void->Float> = null;
}
