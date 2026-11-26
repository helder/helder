import { scenario } from "helder/scenario";

// the real game (main.tsx) at its moments: its model set by name
export const serving = scenario({ name: "Pong/Serve" });
export const rally = scenario({ name: "Pong/Rally", set: { "Game.ball": { x: 300, y: 118 }, "Game.left": 92, "Game.right": 150, "Game.score": [3, 2] } });
export const point = scenario({ name: "Pong/Point scored", set: { "Game.ball": { x: 474, y: 200 }, "Game.right": 60, "Game.score": [4, 2] } });
export const won = scenario({ name: "Pong/You win", set: { "Game.score": [7, 5], "Game.over": true } });
export const lost = scenario({ name: "Pong/You lose", set: { "Game.score": [3, 7], "Game.over": true } });
export const moving = scenario({ name: "Pong/In motion", loop: 3 });
