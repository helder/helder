// A boolean attribute given a string is an error naming the boolean
// (spellCheck={false}; the attribute alone is true).
// expect: BooleanString.hx:7: characters 36-46
// expect: markup: spellCheck="false" is spellCheck={false} (a boolean; spellCheck alone is true)
class BooleanString implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<field spellCheck="false"/>, new helder.ui.Node());
	}
}
