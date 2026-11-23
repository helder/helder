package helder.markup;

import helder.test.Test;

// Which literals are live (Live): a dev build's env() values stay the
// renderer's to bind to the safe area (a padding of calc(env(...) + 12px)
// was set as is, a NaN, in every dev build)
function tests() {
	describe("Live", () -> {
		test("env() values never live", () -> {
			equals(Live.env("env(safe-area-inset-top)"), true);
			equals(Live.env("calc(env(safe-area-inset-bottom) + 16px)"), true);
			equals(Live.env("max(14px, env(safe-area-inset-left))"), true);
			equals(Live.env("12px"), false);
			equals(Live.env("#3b82f6"), false);
		});
		test("fixed attributes", () -> {
			equals(Live.fixed("key"), true);
			equals(Live.fixed("onPress"), true);
			equals(Live.fixed("padding-top"), false);
		});
	});
}
