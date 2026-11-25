// title: Video
// summary: A clip played by the system's decoders in a <Video>: a tap plays and pauses it, the time beside
// tags: media, ui
import helder.asset.Asset;
import helder.media.MemorySource;
import helder.media.ui.MediaTags.*;
import helder.media.ui.VideoNode;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

// A clip (embedded: its bytes in the program) shown by <Video> as an image
// is, contained; it loops, muted, and a tap plays or pauses it. The
// controls are the program's: here its time and a button. (macOS and iOS:
// VideoToolbox and AudioToolbox; the browser: WebCodecs, muted so that it
// autoplays before a gesture; elsewhere the error is shown.)
class Clip implements Markup {
	static function main() {
		var node:Null<VideoNode> = null, time = signal("0.0 s"), error = signal("");
		UiWindow.run(<Surface title="Clip" width={480} height={320} background="#111111" dark={true}>
			<view grow={1} padding={16} row-gap={12}>
				<Video src={new MemorySource(Asset.embed("clip.mp4"))} grow={1} autoplay={true} loop={true} muted={true}
					onTime={t -> time(Std.string(Math.round(t * 10) / 10) + " s")} onError={e -> error(e)} ref={v -> node = v}/>
				<view direction="row" column-gap={12} align-items="center">
					<view:button role="button" focusable padding="6 14" radius={6} background="#27272a" color="#fafafa"
						onPress={() -> if (node != null) node.playing.peek() ? node.pause() : node.play()}>Play / pause</view:button>
					<text color="#a1a1aa">{time}</text>
					<text color="#fca5a5">{error}</text>
				</view>
			</view>
		</Surface>);
	}
}
