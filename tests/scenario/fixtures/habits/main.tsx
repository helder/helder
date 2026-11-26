import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="Habits" width={420} height={780}>
		<App/>
	</Surface>
);
