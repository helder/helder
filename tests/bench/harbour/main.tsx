// The app in a window (`helder run .`); its screens are the stories (app.story.tsx)
import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="Pop-up Harbour" width={1280} height={720}>
		<App/>
	</Surface>
);
