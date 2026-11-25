// title: Liquid Glass
// summary: <glass> over a scrolling list: a toolbar of merging glass buttons and a capsule, the system's on iOS and macOS 26, drawn elsewhere
// tags: ui, glass, docs
// demo: canvas 480x360
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.ui.widgets.Icons;
import helder.view.*;

// Liquid Glass (the docs' Layout page): colourful rows scrolling under a
// glass capsule and a group of glass buttons that merge as they near.
class Glass implements Markup {
	static final colors = ["#ff5e62", "#ffb347", "#5ee7a0", "#3b6cf6", "#a259ff", "#ff7ac6"];

	static function main() {
		UiWindow.run(<Surface title="Liquid Glass" width={480} height={360}>
			<view grow={1} background="#f4f4f5" font-family="Inter" font-size={15}>
				<scroll grow={1} padding={16} row-gap={10}>
					{[for (i in 0...24) <view height={64} radius={14} padding={14} justify="center" background={colors[i % colors.length]}>
						<text color="#ffffff" font-weight={600}>{'Row ${i + 1}'}</text>
					</view>]}
				</scroll>
				<glass position="absolute" left={16} top={12} height={44} padding="0 18" direction="row" align-items="center" column-gap={8} interactive>
					<icon name="search" width={18} height={18}/><text>Search</text>
				</glass>
				<glass-group spacing={12} position="absolute" right={16} top={12} direction="row" column-gap={6}>
					<glass width={44} height={44} align-items="center" justify="center" interactive><icon name="check" width={18} height={18}/></glass>
					<glass width={44} height={44} align-items="center" justify="center" interactive><icon name="more" width={18} height={18}/></glass>
					<glass width={44} height={44} align-items="center" justify="center" interactive><icon name="arrow-right" width={18} height={18}/></glass>
				</glass-group>
			</view>
		</Surface>);
	}
}
