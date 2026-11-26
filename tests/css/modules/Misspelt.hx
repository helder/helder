// (the css lane: a misspelt module name is a type error)
class Misspelt {
	static function main() {
		final card = helder.css.CssModule.load("card.module.css");
		Sys.println(card.cardd);
	}
}
