// React's names are warnings naming HTML's (set as those); rejected for the view's grow (in TypeScript: react-names.tsx).
// expect: markup: htmlFor is for in helder's markup (as HTML writes it)
// expect: markup: className is class in helder's markup (as HTML writes it)
// expect: markup: grow is flexGrow (CSS's name, in camel)
class RejectReactNames implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view className="row"><label htmlFor="name">Name</label><view grow={1}/></view>, new helder.ui.Node());
	}
}
