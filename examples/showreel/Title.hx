import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// The reel's opening (and closing) card: the name's letters popping in one
// by one on springs, a line under it, then what the reel shows, as chips.
class Title implements Markup {
	public static final scene:SceneDef = {name: "title", title: "helder", duration: 3.6, view: view};

	static final WORD = "helder";
	static final CHIPS = ["One draw call", "Springs", "Matched elements", "Variable type", "A million rows", "3D", "Canvas"];
	static final TINTS = [BLUE, VIOLET, MINT, AMBER, CORAL, BLUE, VIOLET];

	public static function view(t:Read<Float>):View {
		return <view flexGrow={1} alignItems="center" justifyContent="center" rowGap={26} background="radial-gradient(circle at 50% 40%, #151a2e 0%, #07080d 70%)" color={INK}
			fontFamily="Inter" motion="bouncy">
			<view flexDirection="row" height={170} alignItems="end">
				<Repeat count={6}>{i -> <Show when={() -> at(t(), 0.15 + i * 0.09)}>
					<text fontFamily="Inter Display" fontSize={160} fontWeight={800} letterSpacing={-6} lineHeight={1} transition="fade pop slide-up(40)">{WORD.charAt(i)}</text>
				</Show>}</Repeat>
				<Show when={() -> at(t(), 0.8)}>
					<view width={30} height={30} borderRadius={15} margin="0 0 26 10" background={MINT} transition="pop"/>
				</Show>
			</view>
			<Show when={() -> at(t(), 1.1)}>
				<text fontSize={22} color={MUTED} transition="fade slide-up(16)">Apps and games in Haxe and TypeScript, native and on the web</text>
			</Show>
			<view flexDirection="row" columnGap={10} height={40}>
				<Repeat count={7}>{i -> <Show when={() -> at(t(), 1.6 + i * 0.11)}>
					<view flexDirection="row" alignItems="center" columnGap={8} padding="8 14" borderRadius={999} background={PANEL} borderWidth={1} borderColor={LINE}
						transition="fade pop">
						<view width={7} height={7} borderRadius={4} background={TINTS[i]}/>
						<text fontSize={14} fontWeight={550}>{CHIPS[i]}</text>
					</view>
				</Show>}</Repeat>
			</view>
		</view>;
	}
}
