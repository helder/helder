import { scenario } from "helder/scenario";
import { ball, left, right, score, over } from "./game";

// the real game (main.tsx's root) at its moments: boot writes its model
export const serving = scenario({ name: "Pong/Serve" });
export const rally = scenario({ name: "Pong/Rally", boot() { ball({ x: 300, y: 118 }); left(92); right(150); score([3, 2]); } });
export const point = scenario({ name: "Pong/Point scored", boot() { ball({ x: 474, y: 200 }); right(60); score([4, 2]); } });
export const won = scenario({ name: "Pong/You win", boot() { score([7, 5]); over(true); } });
export const lost = scenario({ name: "Pong/You lose", boot() { score([3, 7]); over(true); } });
export const moving = scenario({ name: "Pong/In motion", loop: 3 });
