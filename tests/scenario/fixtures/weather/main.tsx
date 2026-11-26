// The app in a window (`helder run .`); its screens are the stories (app.story.tsx)
import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="Ghent weather" width={390} height={844}>
		<App/>
	</Surface>
);
