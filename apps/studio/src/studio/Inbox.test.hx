package studio;

import helder.test.Test;

// The inbox: notes kept until taken, then delivered; as the agent reads them
function tests() {
	describe("Inbox", () -> {
		test("notes taken once, then delivered", () -> {
			var i = new Inbox();
			i.direct("make the fisher a fox", 0);
			i.answer("The user answered \"Which start?\": Dusk", 0);
			equals(i.pending().length, 2);
			var taken = i.take();
			equals(Inbox.text(taken), "The user says: make the fisher a fox\nThe user answered \"Which start?\": Dusk");
			equals(i.take().length, 0);
			equals([for (n in i.list()) n.delivered], [true, true]);
		});
	});
}
