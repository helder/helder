import { UiWindow, Surface } from "helder/ui";
import { Game } from "./game";
import { W, H } from "./pong";

UiWindow.run(
	<Surface title="Pong" width={W} height={H}>
		<Game/>
	</Surface>
);
