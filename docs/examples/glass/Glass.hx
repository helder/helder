// title: Liquid Glass
// summary: <glass> over a scrolling list: a toolbar of merging glass buttons and a capsule, the system's on iOS and macOS 26, drawn elsewhere
// tags: ui, glass, docs
// demo: canvas 480x360
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.ui.controls.Icons;
import helder.view.*;

// Liquid Glass (the docs' Layout page): colourful rows scrolling under a
// glass capsule and a group of glass buttons that merge as they near.
class Glass implements Markup {
	static final colors = ["#ff5e62", "#ffb347", "#5ee7a0", "#3b6cf6", "#a259ff", "#ff7ac6"];

	static function main() {
		UiWindow.run(<Surface title="Liquid Glass" width={480} height={360}>
			<view flexGrow={1} background="#f4f4f5" fontFamily="Inter" fontSize={15}>
				<scroll flexGrow={1} padding={16} rowGap={10}>
					{[for (i in 0...24) <view height={64} borderRadius={14} padding={14} justifyContent="center" background={colors[i % colors.length]}>
						<text color="#ffffff" fontWeight={600}>{'Row ${i + 1}'}</text>
					</view>]}
				</scroll>
				<glass position="absolute" left={16} top={12} height={44} padding="0 18" flexDirection="row" alignItems="center" columnGap={8} interactive>
					<icon name="search" width={18} height={18}/><text>Search</text>
				</glass>
				<view glassSpacing={12} position="absolute" right={16} top={12} flexDirection="row" columnGap={6}>
					<glass width={44} height={44} alignItems="center" justifyContent="center" interactive><icon name="check" width={18} height={18}/></glass>
					<glass width={44} height={44} alignItems="center" justifyContent="center" interactive><icon name="more" width={18} height={18}/></glass>
					<glass width={44} height={44} alignItems="center" justifyContent="center" interactive><icon name="arrow-right" width={18} height={18}/></glass>
				</view>
			</view>
		</Surface>);
	}
}
