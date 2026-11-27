import { platform, imported } from "../modules/packages/browser-conditions";

const checked: "browser" = platform;
if (checked !== "browser" || imported !== "browser") throw new Error("Expected browser exports and imports");
