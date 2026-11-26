// (the css lane: a module's error is the build's, at its line and column)
class Broken {
	static function main() {
		Sys.println(helder.css.CssModule.load("broken.module.css").card);
	}
}
