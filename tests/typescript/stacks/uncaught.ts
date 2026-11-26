// an error nothing catches: the program stops with its stack
class Parser {
	position = 0;

	expect(text: string, c: string) {
		if (text[this.position] !== c) throw new SyntaxError("expected " + c + " at " + this.position);
		this.position++;
	}
}

function parse(text: string) {
	const p = new Parser();
	p.expect(text, "[");
	p.expect(text, "]");
}

parse("[]");
console.log("parsed");
parse("[}");
