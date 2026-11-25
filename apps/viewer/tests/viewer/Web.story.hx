package viewer;

import helder.story.Story;
import helder.view.*;

// The web build at its sample folder, its thumbnails made: helder.run's
// screenshot (store: helder publish --run takes it)
final samples = story({
	name: "Web/Samples",
	store: true,
	caption: "Browse a folder of photos, PDFs and videos",
	width: 1280,
	height: 800,
	render: c -> {
		var x = Fixtures.samples();
		x.browser.go(Samples.ROOT);
		Fixtures.thumbnails(x);
		Shell.view(x);
	}
});
