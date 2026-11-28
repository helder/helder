import helder.ui.fast.StyleModule;

class Descendant {
	static final s = StyleModule.load("descendant.module.css");

	static function main()
		trace(s.list);
}
