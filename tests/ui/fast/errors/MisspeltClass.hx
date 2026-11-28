import helder.ui.StyleModule;

class MisspeltClass {
	static final s = StyleModule.load("errors.module.css");

	static function main()
		trace(s.cardd);
}
