// With hxmc.markup-braces a "{" in a literal's text opens code to its "}":
// one unbalanced is an unterminated literal (write &lbrace;).
// expect: MarkupBrace.hx:6: character 17
// expect: Unterminated markup literal
class MarkupBrace implements helder.view.Markup {
	static var e = <p>if (a) { b</p>;
}
