package helder.canvas;

// A Painter that keeps text as text (doc.Recorder: a PDF's fonts and its
// characters, so they can be selected, searched and copied), not as the
// glyphs' outlines: Glyphs and the DOM facade's fillText and strokeText
// offer it each run of one face, filled (stroke null) or stroked, through
// the painter's transform. false: not taken (a paint it cannot keep),
// drawn as outlines instead.
interface GlyphText {
	function glyphText(run:ShapedRun, paint:Paint, ?stroke:Stroke):Bool;
}
