import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";
import { sample } from "./habits";

UiWindow.run(
	<Surface title="Habits" width={420} height={780}>
		<App habits={sample(new Date())}/>
	</Surface>
);
