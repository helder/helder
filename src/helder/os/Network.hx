package helder.os;

import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Signal;
#if (target.name == "hxmc")
import hxmc.Platform;
#end

enum abstract NetworkKind(String) to String {
	var None = "none";
	var Wifi = "wifi";
	var Cellular = "cellular";
	var Wired = "wired";
	var Other = "other";
}

// whether the device is online, and through what, sampled about once a
// second while the app runs and again when it comes back to the foreground
class Network {
	@:typescript public static var online(get, never):Read<Bool>;
	@:typescript public static var kind(get, never):Read<NetworkKind>;

	static var state:Null<{online:Signal<Bool>, kind:Signal<NetworkKind>}>;

	static function current() {
		if (state != null) return state;
		var k = sample();
		state = {online: Graph.signal(k != None), kind: Graph.signal(k)};
		#if (target.name == "hxmc" && !helder.headless)
		if (!musl()) @:privateAccess App.watchSettings(refresh);
		#elseif js
		for (e in ["online", "offline"])
			js.Syntax.code("globalThis.addEventListener?.({0}, {1})", e, refresh);
		js.Syntax.code("globalThis.navigator?.connection?.addEventListener?.('change', {0})", refresh);
		#end
		return state;
	}

	static function get_online():Read<Bool>
		return current().online;

	static function get_kind():Read<NetworkKind>
		return current().kind;

	static function refresh() {
		var k = sample(), s = state;
		if (s.kind.peek() == k) return;
		s.kind(k);
		s.online(k != None);
		Graph.flush();
	}

	static function sample():NetworkKind {
		#if (target.name == "hxmc")
		#if helder.headless
		return Other;
		#else
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) return web(helder.os.web.Dom.network()); #end
		#if (!helder.os || helder.os == "macos" || helder.os == "ios") if (Platform.os() == Platform.MACOS) return helder.os.apple.AppleNetwork.kind(); #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == Platform.WINDOWS) return helder.os.windows.Network.kind(); #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) return helder.os.android.AndroidNetwork.kind(); #end
		#if (!helder.os || helder.os == "linux") return helder.os.linux.Network.kind(); #else throw "unreachable"; #end
		#end
		#elseif js
		return web(js.Syntax.code("!globalThis.navigator || navigator.onLine === false ? 0 : 1 + Math.max(0, ['wifi', 'cellular', 'ethernet'].indexOf(navigator.connection?.type) + 1)"));
		#else
		return Other;
		#end
	}

	// (the page's: 0 offline, else 1 + wifi, cellular, ethernet's index)
	static function web(v:Int):NetworkKind
		return switch v {
			case 0: None;
			case 2: Wifi;
			case 3: Cellular;
			case 4: Wired;
			case _: Other;
		}

	#if (target.name == "hxmc")
	// (a static Linux executable, musl's: no window back end links there, so App stays out)
	static inline function musl():Bool
		return Platform.os() == Platform.LINUX && Platform.target() < 2;
	#end
}
