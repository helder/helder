import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="Clock" width={360} height={240}>
		<App/>
	</Surface>
);
