package helder.ui;

// how a border is drawn (CSS's border-style; not inherited): Solid, the
// default; Dashed, dashes about three times the side's width long, as many
// on a side as fit it with one at each end, so that the corners are dashes;
// Dotted, round dots as wide as the side, one in each corner and spaced
// about their width apart. The gaps show the background under the border.
enum abstract BorderStyle(Int) {
	var Solid;
	var Dashed;
	var Dotted;
}
