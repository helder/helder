// An element takes its own attributes: a text area's rows on a view is an
// error naming whose they are.
// expect: AttributeElement.hx:7: characters 35-39
// expect: markup: <view> has no attribute rows (<textarea>'s)
class AttributeElement implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view rows={3}/>, new helder.ui.Node());
	}
}
