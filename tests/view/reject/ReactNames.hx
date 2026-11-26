// React's names are warnings naming HTML's, which markup writes (and sets
// them as those); the program here rejected for its view's grow.
// expect: markup: htmlFor is for in helder's markup (as HTML writes it)
// expect: markup: className is class in helder's markup (as HTML writes it)
// expect: markup: grow is flexGrow (CSS's name, in camel)
class ReactNames implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view className="row">
			<label htmlFor="name">Name</label>
			<view grow={1}/>
		</view>, new helder.ui.Node());
	}
}
