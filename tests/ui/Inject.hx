// Scroll input put where the system's comes in, from a thread of its own,
// while the program is busy (AsyncScrollWindow): a wheel's lines every 16 ms
class Inject {
	final thread:Null<sys.thread.Thread> = null;
	final done = new sys.thread.Lock();

	function new() {}

	public static function start(w:helder.os.Window, ms:Int):Inject {
		var i = new Inject();
		i.done.release();
		return i;
	}

	public function join()
		done.wait();
}
