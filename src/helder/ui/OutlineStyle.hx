package helder.ui;

// how an outline is drawn (CSS's outline-style; not inherited): Auto, the
// window's focus ring around the node while it has the focus and the ring
// is shown (the default, as a browser's :focus-visible outline); Solid,
// only the outline the node's style draws (outlineWidth); Dashed and
// Dotted, that outline drawn so (BorderStyle's); None, neither (Tailwind's
// outline-none: a theme drawing its own ring)
enum abstract OutlineStyle(Int) {
	var Auto;
	var Solid;
	var None;
	var Dashed;
	var Dotted;
}
