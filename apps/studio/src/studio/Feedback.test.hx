package studio;

import helder.test.Test;

// The canvas' edge tabs: several on one edge folded into one
function tests() {
	describe("Feedback", () -> {
		test("an edge's tabs folded", () -> {
			equals(Feedback.folded([{text: "New: Rally", fresh: true}]), "New: Rally");
			equals(Feedback.folded([{text: "New: Rally", fresh: true}, {text: "New: You win", fresh: true}, {text: "New: You lose", fresh: true}]), "3 new");
			equals(Feedback.folded([{text: "New: Rally", fresh: true}, {text: "Claude · You win", fresh: false}]), "Claude · You win · 1 more");
		});
	});
}
