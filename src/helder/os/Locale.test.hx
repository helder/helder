package helder.os;

import helder.os.locale.LocaleFallback;
import helder.os.locale.LocaleTag;
import helder.test.Test;

function tests() {
	describe("Locale", () -> {
		test("keeps language preferences in order", () -> {
			var env = ["LANG" => "en_US.UTF-8", "LC_MESSAGES" => "sr_RS.UTF-8@latin", "LANGUAGE" => "fr_CA:fr:fr"];
			equals(LocaleTag.preferred(LocaleFallback.preferred(env.get)).join(","), "fr-CA,fr,sr-Latn-RS");
			env.set("LC_ALL", "C.UTF-8");
			equals(LocaleTag.preferred(LocaleFallback.preferred(env.get)).join(","), "en-US");
			env.set("LC_ALL", "POSIX");
			equals(LocaleTag.preferred(LocaleFallback.preferred(env.get)).join(","), "en-US");
		});
		test("selects CLDR cardinals for integers and fractions", () -> {
			for (c in [
				{tag: "en", counts: [0., 1., -1., 1.2], forms: "other,one,one,other"},
				{tag: "fr", counts: [0., 1., 1.5, 1000000.], forms: "one,one,one,many"},
				{tag: "ar", counts: [0., 1., 2., 7., 15., 100., 3.5], forms: "zero,one,two,few,many,other,other"},
				{tag: "ru-RU", counts: [-21., 2., 11., 25., 101., 1.2], forms: "one,few,many,many,one,other"},
				{tag: "pl", counts: [1., 4., 12., 22., 1.2], forms: "one,few,many,few,other"},
				{tag: "pt-AO-u-nu-latn", counts: [0., 1., 0.5, 1000000.], forms: "other,one,other,many"},
				{tag: "ja", counts: [0., 1., 2.], forms: "other,other,other"},
				{tag: "und", counts: [1.], forms: "other"}
			]) equals([for (n in c.counts) Plural.category(c.tag, n)].join(","), c.forms);
		});
		test("formats with the compact fallback", () -> {
			equals(LocaleFallback.number(-1234567.2345, -1, false, null), "-1,234,567.235");
			equals(LocaleFallback.number(999.9999, -1, false, null), "1,000");
			equals(LocaleFallback.number(0.0001, 2, true, null), "0.01%");
			equals(LocaleFallback.number(2, -1, false, "USD"), "USD 2.00");
			equals(LocaleFallback.number(1e21, 0, false, null), "1,000,000,000,000,000,000,000");
			equals(LocaleFallback.date(new Date(2025, 0, 2, 12, 15, 45), 2, 1), "2025-01-02 12:15");
		});
	});
}
