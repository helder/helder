package helder.os.apple;

import helder.os.Network.NetworkKind;
#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.audio.CoreAudio.Dispatch;
import helder.os.audio.CoreAudio.DispatchWait;
#end

// Network.framework's path monitor, its handler on a queue of its own: the
// first path waited for (briefly) on the first read, later ones kept for
// the next sample.
@:hxmc.unsafe(gc)
class AppleNetwork {
	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
	// (a block is linked where it is compiled, a constant branch or not: Apple's targets only)
	static var last = Other;
	static var started = false;

	public static function kind():NetworkKind {
		if (started) return last;
		started = true;
		var first = Dispatch.dispatch_semaphore_create(0), signalled = false;
		var monitor = Nw.nw_path_monitor_create();
		Nw.nw_path_monitor_set_queue(monitor, Queue.dispatch_queue_create(hxmc.unsafe.Mem.cstr("helder.network"), hxmc.unsafe.Ptr.nil()));
		Nw.nw_path_monitor_set_update_handler(monitor, (path:hxmc.unsafe.Ptr) -> {
			last = of(path);
			if (!signalled) {
				signalled = true;
				Dispatch.dispatch_semaphore_signal(first);
			}
		});
		Nw.nw_path_monitor_start(monitor);
		DispatchWait.dispatch_semaphore_wait(first, Dispatch.dispatch_time(0, 500000000));
		return last;
	}

	// (nw_path_status_satisfied 1; nw_interface_type wifi 1, cellular 2, wired 3)
	static function of(path:hxmc.unsafe.Ptr):NetworkKind {
		if (Nw.nw_path_get_status(path) != 1) return None;
		return Nw.nw_path_uses_interface_type(path, 1) ? Wifi : Nw.nw_path_uses_interface_type(path, 2) ? Cellular : Nw.nw_path_uses_interface_type(path,
			3) ? Wired : Other;
	}
	#else
	public static function kind():NetworkKind
		return Other;
	#end
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
@:hxmc.c @:hxmc.framework("Network") private extern class Nw {
	static function nw_path_monitor_create():hxmc.unsafe.Ptr;
	static function nw_path_monitor_set_queue(m:hxmc.unsafe.Ptr, q:hxmc.unsafe.Ptr):Void;
	static function nw_path_monitor_set_update_handler(m:hxmc.unsafe.Ptr, h:hxmc.objc.Block<hxmc.unsafe.Ptr->Void>):Void;
	static function nw_path_monitor_start(m:hxmc.unsafe.Ptr):Void;
	static function nw_path_get_status(p:hxmc.unsafe.Ptr):Int;
	static function nw_path_uses_interface_type(p:hxmc.unsafe.Ptr, t:Int):Bool;
}

@:hxmc.c private extern class Queue {
	static function dispatch_queue_create(label:hxmc.unsafe.Ptr, attr:hxmc.unsafe.Ptr):hxmc.unsafe.Ptr;
}
#end
