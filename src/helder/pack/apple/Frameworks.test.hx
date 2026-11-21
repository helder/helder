package helder.pack.apple;

import helder.pack.ios.Plist;
import helder.test.Test;

// helder's libraries in a bundle (Frameworks): iOS's framework, its binary
// signed binding its Info.plist and seal; macOS's library, each slice
// signed and the app's seal naming it by cdhash; a universal binary taken
// apart again. (codesign's checks of a whole bundle: the store lane, tests/pack/signing)
function tests() {
	final ios = Frameworks.ios("HelderStore", Frameworks.binary("src", "HelderStore", "ios-sim-arm64"), "ios-sim-arm64");
	final mac = Frameworks.mac("HelderStore", Frameworks.binary("src", "HelderStore", "macos"), null);

	test("iOS: the framework's files, its Info.plist a framework's", () -> {
		equals([for (f in ios) f.path], [
			"Frameworks/HelderStore.framework/HelderStore",
			"Frameworks/HelderStore.framework/Info.plist",
			"Frameworks/HelderStore.framework/_CodeSignature/CodeResources"
		]);
		switch Plist.parse(ios[1].data.toString()) {
			case PDict(d):
				equals(d.get("CFBundlePackageType"), PString("FMWK"));
				equals(d.get("CFBundleIdentifier"), PString("build.helder.store"));
				equals(d.get("CFBundleSupportedPlatforms"), PArray([PString("iPhoneSimulator")]));
			case _: assert(false);
		}
	});
	test("macOS: both slices signed, the seal's requirement either's", () -> {
		final slices = Fat.slices(mac.data);
		equals(slices.length, 2);
		equals(mac.path, "Frameworks/HelderStore.dylib");
		equals(mac.cdhash.toHex(), CodeSign.cdhash(slices[0]).sub(0, 20).toHex());
		equals(mac.requirement.split(" or ").length, 2);
		final seal = MacBundle.codeResources(new Map(), [mac.path => {cdhash: mac.cdhash, requirement: mac.requirement}]).toString();
		assert(seal.indexOf("<key>Frameworks/HelderStore.dylib</key>") > 0 && seal.indexOf("<key>cdhash</key>") > 0);
	});
	test("a universal binary taken apart is its slices", () -> {
		final slices = Fat.slices(mac.data);
		equals(Fat.slices(Fat.make(slices)).map(s -> s.toHex()), slices.map(s -> s.toHex()));
		equals(Fat.slices(slices[0]).length, 1);
	});
}
