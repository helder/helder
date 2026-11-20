import { Format, Locale, Plural } from "helder/os";
import { strings } from "helder/asset";

const t = strings("tests/os/locales");
console.log(Locale.current().length > 0, Locale.preferred()[0] === Locale.current(), Plural.category("pl", 22));
console.log(Format.number(1234.5, { locale: "de-DE", decimals: 2 }));
console.log(Format.number(0.25, { percent: true }), Format.date(new Date(2025, 0, 2, 12), { date: "full" }));
const nl = Locale.current().split("-")[0] === "nl";
console.log(t.get("cart.items", { count: 0 }) === (nl ? "Lege winkelwagen" : "Empty cart"));
console.log(t.get("hello", { name: "Ada" }) === (nl ? "Hallo, Ada!" : "Hello, Ada!"));
