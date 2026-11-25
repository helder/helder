// A struct value (a Vec3) returned by a binding's function, on a renderer
// with no typed setters, is an error when compiling, not a crash.
// expect: MarkupStruct.hx:7: characters
// expect: (a struct value), which a function returning Dynamic cannot return yet
class MarkupStruct implements helder.view.Markup {
	static function main() {
		var e = <div title={new helder.math.Vec3(Math.random(), 0, 0)}/>;
	}
}
