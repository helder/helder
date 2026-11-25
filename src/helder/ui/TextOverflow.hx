package helder.ui;

// what a line too wide for its box shows (CSS's text-overflow): Clip draws
// it on, clipped where the box clips; Ellipsis ends it in "…" within the box;
// Middle keeps the text's start and its end, "…" between, in the lines
// max-lines allows (one by default): a file's name with its extension,
// "E07-uitzonderingen…ster.xlsx", as Finder's (plain text: its spans' not)
enum abstract TextOverflow(Int) {
	var Clip;
	var Ellipsis;
	var Middle;
}
