// an attribute given twice: TypeScript's own error (TS17001) before markup's
// expect: TS17001
import { UiWindow, Surface } from "helder/ui";

function Row() {
	return <button onPress={() => console.log("a")} onPress={() => console.log("b")}><text>hi</text></button>;
}

UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);
