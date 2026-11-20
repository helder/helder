import helder.ui.Router;
import helder.ui.Stack;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;

// helder.ui's Stack with iOS's slide on any platform, for the headless-run
// lane (tests/headless/navigation.json): a push caught mid-transition, an
// edge drag let go short (it springs back) and past half (it pops)
class StackSlide implements Markup {
	static function main() {
		final nav = new Router();
		nav.route("/", _ -> <view tag="list" grow={1} background="#ffffff" padding={12} row-gap={8}>
			{[for (i in 0...5) <view:button tag={"item-" + i} role="button" focusable padding={12} background="#f4f4f5" onPress={() -> nav.go("/item/" + i)}>
				{"Item " + i}</view:button>]}
		</view>).route("/item/:id", p -> <view tag={"detail-" + p.id} grow={1} background="#ffffff" padding={12}><text>{"Detail " + p.id}</text></view>);
		UiWindow.run(<Surface title="Stack" width={320} height={480}>
			<Stack router={nav} transition={Slide}/>
		</Surface>);
	}
}
