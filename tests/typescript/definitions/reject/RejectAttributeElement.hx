// An element takes its own attributes: a text area's rows on a view names whose (in TypeScript: attribute-element.tsx).
// expect: markup: <view> has no attribute rows (<textarea>'s)
class RejectAttributeElement implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view rows={3}/>, new helder.ui.Node());
	}
}
