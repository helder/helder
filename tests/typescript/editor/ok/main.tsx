// helder's globals and TSX, as the build has them
import {UiWindow, Surface} from "helder/ui";

setTimeout(() => console.log("later"), 1);
UiWindow.run(<Surface title="Ok" width={100} height={100}><view/></Surface>);
