// Client.request's https by hand (macOS, iOS: AppleHttp's NSURLSession;
// the network: not a lane's): a GraphQL POST to mock.shop, its status, type
// and the start of its body.
//   helder run tests/async/HttpsProbe.hx            (on a Mac)
//   helder run tests/async/HttpsProbe.hx --target ios -d <simulator>
class HttpsProbe {
	static function main() {
		helder.async.Async.run(_ -> {
			var r = helder.async.http.Client.request("https://apparel-large-catalog.mock.shop/api", {method: "POST", contentType: "application/json",
				text: '{"query":"{ shop { name } }"}'});
			Sys.println('https: ${r.status} ${r.header("content-type")} ${r.text().substr(0, 80)}');
		});
	}
}
