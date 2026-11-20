package helder.os;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

// Local notifications: shown at a time (at), after some seconds (after),
// or now; a tap opens the app and gives onOpen the notification's id,
// those tapped before it was set given when it is. Asking to show them
// is Permissions.request(Notify)'s.
class Notifications {
	@:typescript public static var onOpen(default, set):Null<String->Void> = null;

	static final opened:Array<String> = [];

	// whether it was scheduled (false where the system has none for the app)
	@:typescript public static function schedule(n:{id:String, title:String, ?body:String, ?at:Date, ?after:Float}):Bool {
		var seconds = n.at != null ? (n.at.getTime() - Date.now().getTime()) / 1000 : n.after ?? 0;
		if (seconds < 0) seconds = 0;
		#if (target.name == "hxmc" && !helder.headless)
		if (Platform.os() == Platform.WASI) return helder.os.web.WebNotifications.schedule(n.id, n.title, n.body ?? "", seconds);
		if (Platform.os() == Platform.MACOS) return NotificationsApple.schedule(n.id, n.title, n.body ?? "", seconds, n.at);
		if (Platform.target() >= 9) return helder.os.android.AndroidNotifications.schedule(n.id, n.title, n.body ?? "", seconds);
		#end
		return false;
	}

	@:typescript public static function cancel(id:String) {
		#if (target.name == "hxmc" && !helder.headless)
		if (Platform.os() == Platform.WASI) helder.os.web.WebNotifications.cancel(id);
		else if (Platform.os() == Platform.MACOS) NotificationsApple.cancel(id);
		else if (Platform.target() >= 9) helder.os.android.AndroidNotifications.cancel(id);
		#end
	}

	static function set_onOpen(f:Null<String->Void>) {
		onOpen = f;
		#if (target.name == "hxmc" && !helder.headless)
		// (a tap that started the app: told once something listens)
		if (Platform.os() == Platform.MACOS && f != null) NotificationsApple.listen();
		if (Platform.target() >= 9 && f != null) helder.os.android.AndroidNotifications.listen();
		#end
		if (f != null && opened.length > 0) {
			var ids = opened.copy();
			opened.resize(0);
			for (id in ids) f(id);
		}
		return f;
	}

	@:allow(helder.os) static function open(id:String) {
		var f = onOpen;
		if (f == null) {
			opened.push(id);
			return;
		}
		helder.async.Errors.guard(() -> {
			f(id);
			helder.view.graph.Graph.flush();
		}, "event");
	}
}
