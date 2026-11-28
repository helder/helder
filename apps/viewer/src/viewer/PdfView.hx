package viewer;

import helder.gfx.Color;
import helder.os.Mods;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// A PDF's pages in one scrolling column (PdfDoc, PdfLayout): a scroller
// as large as the layout, the pages near the view made alone (each a
// white sheet with a hairline and a soft shadow, on the light canvas too, its drawing over it as it lands), the
// wheel and a trackpad scrolling it, Control (or Command) with the wheel
// and a pinch zooming about the pointer; the page the view is on in a
// small tag at its top right ("3 / 12"), pressed a field of its number
// (selected): Enter goes to the page typed (clamped; anything but a
// number: nowhere), Escape or leaving it goes nowhere, the keys the
// document's again after (refocus); the pages' text selectable over them
// (PdfTextLayer), Copy in the right click's menu.
@:renderer(helder.ui.view.NodeRenderer)
class PdfView implements Markup {
	// (veiled: its pages not shown, laid out still: a page in flight over them)
	public static function make(doc:PdfDoc, ?veiled:Void->Bool, ?refocus:Void->Void):View {
		var scroller:Null<Node> = null, editing = signal(false);
		// (the model's moves: a page gone to, a zoom kept about its point; one out of sight, no bar shown for it)
		renderEffect(() -> doc.scroll(), s -> if (scroller != null) {
			scroller.scrollX = s.x;
			scroller.scrollY = s.y;
			if (s.quiet && scroller.ui != null) scroller.ui.rested(scroller);
		});
		// (the field closed: to the page typed, if any; the keys the document's)
		function typed(text:Null<String>) {
			if (!editing.peek()) return;
			editing(false);
			var n = text == null ? null : PdfDoc.typed(text, doc.pages);
			if (n != null) doc.goTo(n);
			if (refocus != null) refocus();
		}
		function sized() {
			var n = scroller;
			if (n == null) return;
			if (n.ui != null) doc.density = n.ui.scale;
			doc.view(n.width, n.height);
		}
		return <view tag="pdf" position="absolute" inset={0} onPointerDown={PdfTextLayer.menu}>
			<scroll tag="pdf-scroll" position="absolute" inset={0} opacity={veiled != null && veiled() ? 0 : 1} onResize={_ -> sized()} ref={(n:Node) -> {
				scroller = n;
				n.onScroll = () -> doc.scrolled(n.scrollX, n.scrollY);
			}} onWheel={e -> if (e.mods & (Mods.CONTROL | Mods.META) != 0) {
					doc.zoomBy(Math.exp(-e.deltaY * Math.log(1.25) / 40), e.localX, e.localY);
					e.preventDefault();
				}}>
				<view tag="pdf-pages" flexShrink={0} width={() -> {
					doc.zoom();
			doc.laid();
					doc.layout.width();
				}} height={() -> {
					doc.zoom();
			doc.laid();
					doc.layout.height();
				}}>
					<For each={() -> doc.shown()}>{i -> page(doc, i())}</For>
					{PdfTextLayer.of(doc)}
				</view>
			</scroll>
			<Show when={doc.pages > 1}>
				<view position="absolute" top={12} right={16} flexDirection="row" alignItems="center" columnGap={4} padding="3 9" borderRadius={8} fontSize={12}
					background={Look.ref.raised} color={Look.ref.fg2} borderWidth={1} borderColor={Look.ref.edge} shadows={[{x: 0, y: 2, blur: 8, color: Color.rgba(0, 0.15)}]}>
					<Show when={!editing()}>
						<button tag="page-indicator" focusable={false} aria-label="Go to page" onPress={() -> editing(true)}>
							<text>{() -> '${doc.page() + 1} / ${doc.pages}'}</text>
						</button>
					</Show>
					<Show when={editing()}>
						{field(doc, typed)}
						<text>{'/ ${doc.pages}'}</text>
					</Show>
				</view>
			</Show>
		</view>;
	}

	// (the page's number to type over, selected; Enter: done(its text), Escape or left: done(null))
	static function field(doc:PdfDoc, done:Null<String>->Void):View {
		var text = Std.string(doc.page.value + 1);
		return <field tag="page-field" value={text} aria-label="Page number" width={Std.string(doc.pages).length * 8 + 12} padding="0 3"
			borderRadius={4} background={Look.ref.well} borderWidth={1} borderColor={Look.ref.accent} color={Look.ref.fg} textAlign="right"
			onInput={e -> text = e.text}
			onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.ESCAPE) {
				done(e.key == Key.ENTER ? text : null);
				e.preventDefault();
				e.stop();
			}}
			onBlur={_ -> done(null)}
			ref={(n:Node) -> helder.ui.Clock.add(_ -> {
				n.focus();
				n.select(0, text.length);
				false;
			})}/>;
	}

	static function page(doc:PdfDoc, i:Int):View
		return <view tag="page" position="absolute" background="#ffffff" borderWidth={1} borderColor="rgba(0,0,0,0.08)" shadows={[{x: 0, y: 1, blur: 4, color: Color.rgba(0, 0.28)}]} left={() -> {
			doc.zoom();
			doc.laid();
			doc.layout.left(i);
		}} top={() -> {
			doc.zoom();
			doc.laid();
			doc.layout.top(i);
		}} width={() -> {
			doc.zoom();
			doc.laid();
			doc.layout.pageWidth(i);
		}} height={() -> {
			doc.zoom();
			doc.laid();
			doc.layout.pageHeight(i);
		}}>
			<image tag="page-image" width="100%" height="100%" src={() -> {
				doc.rendered();
				doc.image(i);
			}}/>
		</view>;
}
