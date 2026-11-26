package helder.text.hyphenation;

// A language's hyphenation patterns as generate.mjs packs them (Liang's,
// TeX's): its BCP 47 tag, the fewest letters before and after a break
// (TeX's lefthyphenmin and righthyphenmin), its letters (each in lower
// case then its upper case, a space after each), the patterns (sorted,
// each the length it shares with the one before as a character, U+0001
// plus it, then the rest of its TeX form) and the exceptions (hyphenated
// words, spaces between them). helder.text.Hyphenator reads them.
class Patterns {
	public final tag:String;
	public final left:Int;
	public final right:Int;
	public final alphabet:String;
	public final patterns:String;
	public final exceptions:String;

	public function new(tag:String, left:Int, right:Int, alphabet:String, patterns:String, exceptions:String) {
		this.tag = tag;
		this.left = left;
		this.right = right;
		this.alphabet = alphabet;
		this.patterns = patterns;
		this.exceptions = exceptions;
	}
}
