import helder.ui.StyleModule;

class Descendant {
	static final s = StyleModule.load("descendant.module.css");

	static function main()
		trace(s.list);
}
