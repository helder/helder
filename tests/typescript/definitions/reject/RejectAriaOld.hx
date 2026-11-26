// Assistive technology's attributes are ARIA's, as HTML writes them (in TypeScript: aria-old.tsx).
// expect: markup: label is aria-label (HTML's ARIA attribute)
class RejectAriaOld implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<button label="Close"/>, new helder.ui.Node());
	}
}
