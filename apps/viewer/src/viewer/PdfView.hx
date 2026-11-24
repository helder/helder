package viewer;

import helder.ui.Key;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A PDF's pages in one scrolling column (PdfDoc, PdfLayout): a scroller
// as large as the layout, the pages near the view made alone (each a
// white sheet with a soft shadow, its drawing over it as it lands), the
// wheel and a trackpad scrolling it, Control (or Command) with the wheel
// and a pinch zooming about the pointer; the page the view is on in a
// small tag at its top right ("3 / 12").
class PdfView implements Markup {
	public static function make(doc:PdfDoc):View {
		var scroller:Null<Node> = null;
		// (the model's moves: a page gone to, a zoom kept about its point)
		renderEffect(() -> doc.scroll(), s -> if (scroller != null) {
			scroller.scrollX = s.x;
			scroller.scrollY = s.y;
		});
		function sized() {
			var n = scroller;
			if (n == null) return;
			if (n.ui != null) doc.density = n.ui.scale;
			doc.view(n.width, n.height);
		}
		return <view tag="pdf" position="absolute" inset={0}>
			<scroll tag="pdf-scroll" position="absolute" inset={0} onResize={_ -> sized()} ref={(n:Node) -> {
				scroller = n;
				n.onScroll = () -> doc.scrolled(n.scrollX, n.scrollY);
			}} onWheel={e -> if (e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0) {
					doc.zoomBy(Math.exp(-e.deltaY * Math.log(1.25) / 40), e.localX, e.localY);
					e.preventDefault();
				}}>
				<view tag="pdf-pages" shrink={0} width={() -> {
					doc.zoom();
					doc.layout.width();
				}} height={() -> {
					doc.zoom();
					doc.layout.height();
				}}>
					<For each={() -> doc.shown()}>{i -> page(doc, i())}</For>
				</view>
			</scroll>
			<Show when={doc.pages > 1}>
				<text tag="page-indicator" position="absolute" top={12} right={16} padding="3 9" radius={8} font-size={12} background={Look.ref.raised}
					color={Look.ref.fg2} border-width={1} border-color={Look.ref.edge} shadow="0 2px 8px rgba(0,0,0,0.15)" pointer-events="none">{() -> '${doc.page() + 1} / ${doc.pages}'}</text>
			</Show>
		</view>;
	}

	static function page(doc:PdfDoc, i:Int):View
		return <view tag="page" position="absolute" background="#ffffff" shadow="0 1px 4px rgba(0,0,0,0.28)" left={() -> {
			doc.zoom();
			doc.layout.left(i);
		}} top={() -> {
			doc.zoom();
			doc.layout.top(i);
		}} width={() -> {
			doc.zoom();
			doc.layout.pageWidth(i);
		}} height={() -> {
			doc.zoom();
			doc.layout.pageHeight(i);
		}}>
			<image tag="page-image" width="100%" height="100%" src={() -> {
				doc.rendered();
				doc.image(i);
			}}/>
		</view>;
}
