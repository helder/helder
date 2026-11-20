package helder.os.android;

import helder.os.Network.NetworkKind;
import hxmc.unsafe.*;

// ConnectivityManager's active network: online when it reaches the
// internet (NET_CAPABILITY_INTERNET), its kind its transport.
@:hxmc.android @:helder.android.permission("ACCESS_NETWORK_STATE", "INTERNET")
@:hxmc.unsafe(gc)
class AndroidNetwork {
	public static function kind():NetworkKind {
		var k = Other;
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var manager = Jni.service("connectivity");
			if (manager.isNull()) return;
			var cm = Jni.cls("android.net.ConnectivityManager"), caps = Jni.cls("android.net.NetworkCapabilities");
			var network = Jni.obj(manager, Jni.method(cm, "getActiveNetwork", "()Landroid/net/Network;"));
			var c = network.isNull() ? Ptr.nil() : Jni.obj(manager, Jni.method(cm, "getNetworkCapabilities",
				"(Landroid/net/Network;)Landroid/net/NetworkCapabilities;"), network.toI64());
			if (c.isNull() || !Jni.bool(c, Jni.method(caps, "hasCapability", "(I)Z"), 12)) {
				k = None;
				return;
			}
			// (TRANSPORT_CELLULAR 0, WIFI 1, ETHERNET 3)
			var has = Jni.method(caps, "hasTransport", "(I)Z");
			k = Jni.bool(c, has, 1) ? Wifi : Jni.bool(c, has, 0) ? Cellular : Jni.bool(c, has, 3) ? Wired : Other;
		});
		return k;
	}
}
