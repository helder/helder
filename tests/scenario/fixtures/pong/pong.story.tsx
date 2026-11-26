import { story } from "helder/story";
import { Court, serve, W } from "./pong";
import { Game } from "./game";

export const serving = story({ name: "Court/Serve", width: 480, height: 320, render: () => <Court state={serve()}/> });
export const rally = story({ name: "Court/Rally", width: 480, height: 320, render: () =>
	<Court state={{ ...serve(), ball: { x: 300, y: 118 }, left: 92, right: 150, score: [3, 2] }}/> });
export const paused = story({ name: "Court/Paused", width: 480, height: 320, render: () =>
	<Court state={{ ...serve(), ball: { x: 300, y: 118 }, left: 92, right: 150, score: [3, 2], paused: true }}/> });
export const point = story({ name: "Court/Point scored", width: 480, height: 320, render: () =>
	<Court state={{ ...serve(), ball: { x: W - 6, y: 200 }, right: 60, score: [4, 2] }}/> });
export const won = story({ name: "Court/You win", width: 480, height: 320, render: () =>
	<Court state={{ ...serve(), score: [7, 5], over: true }}/> });
export const lost = story({ name: "Court/You lose", width: 480, height: 320, render: () =>
	<Court state={{ ...serve(), score: [3, 7], over: true }}/> });
export const moving = story({ name: "Court/In motion", width: 480, height: 320, loop: 3, render: () => <Game/> });
