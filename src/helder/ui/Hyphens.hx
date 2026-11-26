package helder.ui;

// whether words are hyphenated where lines break (CSS's hyphens): Manual at
// soft hyphens (U+00AD, &shy;) alone; None not even there; Auto also where
// the node's language (Node.lang) hyphenates them, by its patterns
// (helder.text.Hyphenation: the languages the program added)
enum abstract Hyphens(Int) {
	var None;
	var Manual;
	var Auto;
}
