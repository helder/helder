package story;

import helder.story.Story;
import helder.ui.Selection;
import helder.ui.view.UiFlow.VirtualGrid;
import helder.view.View;

// a grid's cells styled by the selection (Beta to Delta: a Shift range)
final selected = story({
	name: "VirtualGrid/selection",
	width: 268,
	height: 150,
	render: _ -> {
		var files = ["Alpha", "Beta", "Cedar", "Delta", "Elm", "Fir", "Ginkgo", "Hazel"];
		var pick = new Selection(i -> files[i], () -> files.length);
		pick.select(1);
		pick.extend(3);
		function on(file:String):Bool
			return pick.version() >= 0 && pick.has(file);
		View.view(<VirtualGrid each={files} by={s -> s} cellWidth={75} cellHeight={36} selection={pick} label="Files">{(file, i) ->
			<text padding={6} background={on(file()) ? "#2563eb" : "#e2e8f0"} color={on(file()) ? "#ffffff" : "#0f172a"}>
				{file() + (on(file()) ? " ✓" : "")}
			</text>}</VirtualGrid>);
	}
});
