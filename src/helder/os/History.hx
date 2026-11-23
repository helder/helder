package helder.os;

#if (!helder.os || helder.os == "web")
import helder.os.web.Dom;
#end
import hxmc.Platform;
import hxmc.unsafe.*;

// The page's history in a browser (WebAssembly), an app's own while it owns
// it (helder.ui's Stack: a Router's entries, a URL each): push, replace
// and go back by n; the browser's back and forward come to onPop with how
// many entries back it went (forward is undone). While owned, App.backDepth
// keeps no entry of its own. Elsewhere none of it does anything and
// location is null.
@:hxmc.unsafe(gc)
class History {
	static var onPop:Null<Int->Void> = null;

	// the page's path and query (location's)
	public static function location():Null<String> {
		if (Platform.os() == Platform.WASI) {
			#if (!helder.os || helder.os == "web")
			var h = Dom.location();
			if (h != 0) return @:privateAccess helder.os.web.CanvasWindow.take(h);
			#end
		}
		return null;
	}

	public static function own(popped:Int->Void) {
		onPop = popped;
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) Dom.history_own(Callback.addr(pop)); #end
	}

	public static function release() {
		onPop = null;
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) Dom.history_own(Ptr.nil()); #end
	}

	public static function push(url:String)
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) Arena.scoped(a -> Dom.history_push(a.cstring(url), 1)); #else {} #end

	public static function replace(url:String)
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) Arena.scoped(a -> Dom.history_push(a.cstring(url), 0)); #else {} #end

	public static function go(n:Int)
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) Dom.history_go(n); #else {} #end

	@:hxmc.callback static function pop(steps:Int):Int {
		var f = onPop;
		if (f != null) helder.async.Errors.guard(() -> {
			f(steps);
			helder.view.graph.Graph.flush();
		}, "event");
		return 0;
	}
}
