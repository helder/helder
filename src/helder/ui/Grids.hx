package helder.ui;

// A style's grid terms, linked where a program says grid (a style's display
// Grid or a grid field, written in a literal or markup's attributes:
// Style.of and the renderer call use).
class Grids {
	public static inline function use()
		Resolve.grids = fill;

	// (a style's grid as the terms GridFlow reads, GridTerms', into its box's rare part)
	@:allow(helder.ui) static function fill(p:Style.Props, rare:() -> helder.ui.box.BoxRare) {
		if (p.gridTemplateColumns != null) rare().gridTemplateColumns = GridTerms.tracks(p.gridTemplateColumns);
		if (p.gridTemplateRows != null) rare().gridTemplateRows = GridTerms.tracks(p.gridTemplateRows);
		if (p.gridTemplateAreas != null) rare().gridTemplateAreas = GridTerms.areas(p.gridTemplateAreas);
		if (p.gridAutoColumns != null) rare().gridAutoColumns = GridTerms.tracks(p.gridAutoColumns);
		if (p.gridAutoRows != null) rare().gridAutoRows = GridTerms.tracks(p.gridAutoRows);
		if (p.gridAutoFlow != null) rare().gridAutoFlow = GridTerms.flow(p.gridAutoFlow);
		if (p.gridRow != null || p.gridColumn != null || p.gridArea != null) {
			var lines = p.gridArea != null ? GridTerms.area(p.gridArea) : null;
			var row = p.gridRow != null ? GridTerms.lines(p.gridRow) : lines != null ? [lines[0], lines[2]] : null;
			var col = p.gridColumn != null ? GridTerms.lines(p.gridColumn) : lines != null ? [lines[1], lines[3]] : null;
			var g = rare().gridLines.copy();
			if (row != null) {
				g[0] = row[0];
				g[1] = row[1];
			}
			if (col != null) {
				g[2] = col[0];
				g[3] = col[1];
			}
			rare().gridLines = g;
		}
	}
}
