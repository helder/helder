package helder.view;

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
		test("ids name a web build's files by label, as hxmc's -D hxmc.paths does", () -> {
			var src = "a\n  color=\"#fff\"";
			Live.paths("/home/ann/pong=<project>,/home/ann/pong/node_modules/helder/src=<helder>");
			equals(Live.id("/home/ann/pong/pong.tsx", src, 10, "color"), "<project>/pong.tsx:2:9:color");
			equals(Live.id("/home/ann/pong/node_modules/helder/src/helder/ui/Bar.hx", src, 0, "number"), "<helder>/helder/ui/Bar.hx:1:1:number");
			equals(Live.id("C:\\Users\\ann\\x.tsx", src, 0, "text"), "C:\\Users\\ann\\x.tsx:1:1:text");
			Live.paths(null);
			equals(Live.id("/home/ann/pong/pong.tsx", src, 0, "color"), "/home/ann/pong/pong.tsx:1:1:color");
		});
	});
}
