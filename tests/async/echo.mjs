// The browser tests' server side of Client.request and WebSocket.open:
// POST /echo answers "<method>|<body>", /echo-ws a WebSocket echoing each
// text message (RFC 6455 by hand: no library).
import { createHash } from 'node:crypto';

export function echo(req, res) {
	if (new URL(req.url, 'http://x').pathname !== '/echo') return false;
	const chunks = [];
	req.on('data', (c) => chunks.push(c));
	req.on('end', () => res.writeHead(200, { 'content-type': 'text/plain', 'x-echo': 'yes' }).end(req.method + '|' + Buffer.concat(chunks).toString()));
	return true;
}

export function echoSockets(server) {
	server.on('upgrade', (req, socket) => {
		if (new URL(req.url, 'http://x').pathname !== '/echo-ws') return socket.destroy();
		const accept = createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
		socket.write(`HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: ${accept}\r\n\r\n`);
		let buf = Buffer.alloc(0);
		socket.on('data', (d) => {
			buf = Buffer.concat([buf, d]);
			while (buf.length >= 2) {
				const op = buf[0] & 15;
				let n = buf[1] & 127, at = 2;
				if (n === 126) { n = buf.readUInt16BE(2); at = 4; } else if (n === 127) { n = Number(buf.readBigUInt64BE(2)); at = 10; }
				if (buf.length < at + 4 + n) return;
				const mask = buf.subarray(at, at + 4), data = Buffer.from(buf.subarray(at + 4, at + 4 + n));
				for (let i = 0; i < n; i++) data[i] ^= mask[i & 3];
				buf = buf.subarray(at + 4 + n);
				if (op === 8) return socket.end(Buffer.from([0x88, 0]));
				if (op !== 1) continue;
				const out = Buffer.from('echo ' + data.toString());
				const head = out.length < 126 ? Buffer.from([0x81, out.length]) : out.length < 65536 ? Buffer.from([0x81, 126, out.length >> 8, out.length & 255]) : null;
				socket.write(Buffer.concat([head, out]));
			}
		});
	});
}
