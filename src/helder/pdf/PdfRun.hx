package helder.pdf;

// A line of a page's text as it is placed (Pdf.runs): its characters, a
// space where a gap is wide enough for one, and its glyphs' boxes. A page's
// runs joined by newlines are its Pdf.text.
class PdfRun {
	public final text:String;
	public final glyphs:Array<PdfGlyph>;

	public function new(text:String, glyphs:Array<PdfGlyph>) {
		this.text = text;
		this.glyphs = glyphs;
	}
}
