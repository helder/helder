package helder.asset;

import helder.test.Test;

function tests() {
	describe("String catalogues", () -> {
		test("formats named arguments and exact and CLDR cases", () -> {
			var message = new StringMessage("{count, plural, =0 {Empty} =1 {Only for {name}} one {# item for {name}} other {# items for {name}}}");
			equals(message.params.get("count"), true);
			equals(message.params.get("name"), false);
			equals(message.format("en", {count: 0, name: "Ada"}), "Empty");
			equals(message.format("en", {count: 1, name: "Ada"}), "Only for Ada");
			equals(message.format("en", {count: 2, name: "Ada"}), "2 items for Ada");
			equals(message.format("en", {count: -1, name: "Ada"}), "-1 item for Ada");
		});
		test("rejects unsupported syntax and incomplete plurals", () -> {
			throws(() -> new StringMessage("{count, plural, one {One}}"));
			throws(() -> new StringMessage("{count, select, other {Other}}"));
			throws(() -> new StringMessage("{count, plural, other {{count}}}"));
			throws(() -> new StringMessage("Hello {name"));
			throws(() -> StringMessage.catalogue('{"title":42}'));
		});
		test("tries the exact tag, its language, then the default", () -> {
			equals(@:privateAccess Strings.candidates("nl-BE-u-nu-latn", "en").join(","), "nl-BE,nl,en");
			equals(@:privateAccess Strings.candidates("nl-BE", "nl").join(","), "nl-BE,nl");
			equals(@:privateAccess Strings.candidates("en", "en").join(","), "en");
		});
	});
}
