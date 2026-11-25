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
		// (the desktop's shell, as the page is drawn: the tree is taken at a phone's size)
		Shell.view(x, () -> helder.ui.SizeClass.Expanded);
	}
});
