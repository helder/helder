import helder.ui.fast.StyleModule;

class MisspeltClass {
	static final s = StyleModule.load("errors.module.css");

	static function main()
		trace(s.cardd);
}
