package viewer;

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
		n.style.position = Absolute;
		n.style.left = n.style.top = 0;
		n.style.zIndex = 1;
		n.style.pointerEvents = None;
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
			n.style.width = l.width();
			n.style.height = l.height();
			for (i => p in pages) {
				p.style.left = l.left(i);
				p.style.top = l.top(i);
				p.style.width = l.pageWidth(i);
				p.style.height = l.pageHeight(i);
			}
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
