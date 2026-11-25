package viewer;

import helder.story.Story;
import helder.ui.Clock;
import helder.ui.controls.Standard;
import helder.ui.menu.TouchMenu;
import helder.view.*;
import viewer.Phone.PhoneState;

// The viewer on a phone, the design's screens (their trees in
// Phone.story.snap; store: true, the stores' screenshots): Browse, a
// folder's grid and its list, select mode, a long press's menu, a photo
// full size, its info sheet, a PDF; and on a tablet, the folder with its
// sidebar's drawer open. The web build's sample folder, its thumbnails made.
final browse = story({name: "Phone/Browse", store: true, caption: "Your folders, on your phone", render: c -> phone(p -> {})});

final grid = story({
	name: "Phone/Folder",
	store: true,
	caption: "Every photo, PDF and video at a glance",
	render: c -> phone(p -> p.browse(Samples.ROOT))
});

final list = story({
	name: "Phone/List",
	render: c -> phone(p -> {
		p.browse(Samples.ROOT);
		p.x.browser.layout(List);
	})
});

final select = story({
	name: "Phone/Select",
	render: c -> phone(p -> {
		p.browse(Samples.ROOT);
		p.selecting(true);
		for (n in ["Murmuration.jpg", "Planet.jpg", "Starlings.jpg"])
			p.x.browser.selection.toggle(p.x.browser.indexOf(n));
		p.x.browser.selectionChanged();
	})
});

final menu = story({
	name: "Phone/Long press",
	render: c -> phone(p -> {
		p.browse(Samples.ROOT);
		// (laid out first: the menu over the tile it was pressed on)
		var ui = p.node?.ui;
		if (ui == null) return;
		// (the grid's rows made once its width is known: a few rounds)
		for (_ in 0...4) {
			helder.view.graph.Graph.flush();
			helder.ui.Clock.finish();
			ui.update();
		}
		{
			var t = p.node?.find("tile-Murmuration.jpg");
			if (t == null || t.ui == null) return;
			p.x.browser.select("Murmuration.jpg");
			TouchMenu.open(t.ui, [
				{label: "Open", run: () -> {}},
				{label: "Get Info", run: () -> {}},
				{label: "Open in…", run: () -> {}},
				{label: "Select", run: () -> {}},
				{label: "Move to Trash", destructive: true, separated: true, run: () -> {}}
			], t.windowBounds(), <view grow={1}>{Tiles.large({name: "Murmuration.jpg", kind: File, size: 0, modified: 0, created: 0})}</view>, true,
				t.sheet());
		}
	})
});

final full = story({
	name: "Phone/Full size",
	store: true,
	caption: "Swipe through them full size",
	render: c -> phone(p -> {
		p.browse(Samples.ROOT);
		p.open("Starlings.jpg");
	})
});

final info = story({
	name: "Phone/Info",
	render: c -> phone(p -> {
		p.browse(Samples.ROOT);
		p.open("Planet.jpg");
		p.showInfo(true);
	})
});

final pdf = story({
	name: "Phone/PDF",
	render: c -> phone(p -> {
		p.browse(Samples.ROOT);
		p.open("About Viewer.pdf");
	})
});

final tablet = story({
	name: "Tablet/Folder, sidebar",
	width: 820,
	height: 1180,
	render: c -> {
		var x = samples();
		x.choose(Samples.ROOT);
		Fixtures.thumbnails(x);
		x.sidebarOpen(true);
		Shell.view(x, () -> helder.ui.SizeClass.Medium);
	}
});

// (the sample folder's explorer, its thumbnails made as its folders are shown)
private function samples():Explorer {
	var x = Fixtures.samples();
	var listed = x.browser.onItems;
	x.browser.onItems = () -> {
		if (listed != null) listed();
		Fixtures.thumbnails(x);
	};
	return x;
}

// (the phone's shell, brought to its moment by at)
private function phone(at:PhoneState->Void):View {
	Kinds.utc = true;
	var x = samples();
	return <Standard.Themed look={Shell.look}><Phone.Root x={x} at={p -> {
		at(p);
		Fixtures.thumbnails(x);
	}}/></Standard.Themed>;
}
