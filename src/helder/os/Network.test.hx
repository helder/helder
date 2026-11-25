package helder.os;

import helder.os.Network.NetworkKind;
import helder.test.Test;

// Network: Linux's default route read from /proc's tables (IPv4's, else
// IPv6's), the kinds' names; the signals' values are each system's
function tests() {
	test("Linux's default route: its interface", () -> {
		var v4 = "Iface\tDestination\tGateway\tFlags\nwlan0\t0010A8C0\t00000000\t0001\neth0\t00000000\t0100A8C0\t0003\n";
		equals(@:privateAccess helder.os.linux.Network.route(v4, ""), "eth0");
		equals(@:privateAccess helder.os.linux.Network.route("Iface\tDestination\tGateway\tFlags\neth0\t00000000\t0100A8C0\t0002\n", ""), null);
		var v6 = "00000000000000000000000000000000 00 00000000000000000000000000000000 00 00000000000000000000000000000000 ffffffff 00000001 00000000 00200200 lo\n"
			+ "00000000000000000000000000000000 00 00000000000000000000000000000000 00 fe800000000000000000000000000001 00000400 00000001 00000000 00000003 wlp2s0\n";
		equals(@:privateAccess helder.os.linux.Network.route("", v6), "wlp2s0");
	});
	test("the kinds, as TypeScript has them", () -> {
		equals([NetworkKind.None, Wifi, Cellular, Wired, Other].map(k -> (k : String)), ["none", "wifi", "cellular", "wired", "other"]);
		equals(Network.online() == (Network.kind() != None), true);
	});
}
