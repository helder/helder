import helder.asset.Asset;
import helder.os.Format;
import helder.os.Locale;
import hxmc.Platform;

class LocaleCheck {
	static function main() {
		var tags = Locale.preferred(), date = Date.fromTime(1735819200000.0);
		var en = Format.number(1234.5, {locale: "en-US", decimals: 2});
		var de = Format.number(1234.5, {locale: "de-DE", decimals: 2});
		var pct = Format.number(0.25, {locale: "en-US", percent: true});
		var yen = Format.number(200, {locale: "en-US", currency: "JPY", decimals: 0});
		var us = Format.date(date, {locale: "en-US", date: Short, time: Short});
		var germany = Format.date(date, {locale: "de-DE", date: Full, time: Medium});
		if (tags.length == 0 || tags[0] != Locale.current()) throw "Expected a preferred locale";
		var linux = Platform.os() == Platform.LINUX && Platform.target() < 9;
		if (en != "1,234.50" || de != (linux ? "1,234.50" : "1.234,50") || pct != "25%" || !StringTools.endsWith(yen, "200"))
			throw 'Unexpected numbers: $en / $de / $pct / $yen';
		if (us.indexOf(":") < 0 || germany.indexOf("2025") < 0 || germany.indexOf(":") < 0 || us == germany)
			throw 'Unexpected dates: $us / $germany';
		var t = Asset.strings("locales");
		var nl = tags[0].split("-")[0] == "nl";
		if (t.title() != (nl ? "Berichten" : "Messages") || t.hello({name: "Ada"}) != (nl ? "Hallo, Ada!" : "Hello, Ada!")
			|| t.cart.items({count: 2}) != (nl ? "2 artikelen" : "2 items")) throw "Unexpected catalogue result";
		Sys.println('locale: ${tags.join(",")} $en / $de / $pct / $yen / $us / $germany');
		if (Platform.os() == Platform.WASI) {
			helder.view.graph.Graph.effect(() -> t.title(), title -> {
				Sys.println('title: $title');
				Sys.stdout().flush();
			});
			helder.view.graph.Graph.flush();
		}
	}
}
