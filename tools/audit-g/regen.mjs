// Audit G: what the renames' sources write, written again: the TypeScript
// declarations of every invocation CI checks (tests/lanes/Cli.hx's
// declarations()) and helder/math's and helder/gfx's TypeScript.
//   node tools/audit-g/regen.mjs
import { execFileSync } from "node:child_process";
import { root } from "./lib.mjs";

const run = (args) => execFileSync(process.execPath, args, { cwd: root, stdio: "inherit" });
run(["src/helder/math/typescript.mjs"]);
run(["src/helder/gfx/typescript.mjs"]);
const d = "src/helder/typescript/api/declarations.mjs";
const scene = ["tests/3d/ts", "tests/gfx", "examples/triangle", "examples/cube", "examples/instances", "examples/mips", "examples/formats"].flatMap((p) => ["--cp", p]);
run([d]);
run([d, "--cp", "tests/view", "--cp", "tests/ui", "TestTypeScript", "UiTypeScript"]);
run([d, "--cp", "tests/typescript/platform", "PlatformTypeScript"]);
run([d, ...scene, "frames.FramesTypeScript"]);
