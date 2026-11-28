package viewer;

import helder.ui.Style;
import helder.pdf.ui.PdfText;
import helder.ui.Event;
import helder.ui.Node;
import helder.view.graph.Graph.renderEffect;

// A PDF's pages' text (helder.pdf.ui's PdfText, one a page) as one
// selectable layer over them in its PdfView's column: placed as the
// document's layout places the pages, each one's text its decode's, a
// selection begun reading the other pages' too (Mod+A and Copy over them all)
class PdfTextLayer {
	public static function of(doc:PdfDoc):Node {
		var n = new Node("pdf-text");
		n.selectable = true;
		n.style = Style.of({position: Absolute, left: 0, top: 0, zIndex: 1, pointerEvents: None});
		var pages = [for (i in 0...doc.pages) new PdfText(doc.layout.sizes[i].width)];
		for (p in pages) {
			p.onSelect = doc.wantText;
			n.append(p);
		}
		renderEffect(() -> {
			doc.zoom();
			doc.laid();
		}, _ -> {
			var l = doc.layout;
			n.style = n.style.with({width: l.width(), height: l.height()});
			for (i => p in pages)
				p.style = p.style.with({left: l.left(i), top: l.top(i), width: l.pageWidth(i), height: l.pageHeight(i)});
		});
		renderEffect(() -> doc.texted(), _ -> for (i => p in pages) p.text = doc.text(i));
		return n;
	}

	// (a right press: the PDF's context menu, Copy the selection's)
	public static function menu(e:Event) {
		if (e.button != 3 || e.target.ui == null) return;
		e.preventDefault();
		helder.ui.menu.Menus.popup(e.target.ui, ViewerActions.pdf, e.x, e.y, e.target);
	}
}
