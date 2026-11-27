function failure(f: () => unknown): string {
    try {
        f();
        return "no error";
    } catch (e) {
        return (e as Error).name;
    }
}

const encoder = new TextEncoder();
const text = "Aé😀\ud800B\udc80";
const bytes = encoder.encode(text);
console.log(encoder.encoding, encoder.encode().length, bytes.join(","));
const backing = new Uint8Array(9).fill(9);
const dest = backing.subarray(1, 8);
console.log(encoder.encodeInto("Aé😀Z", dest), backing.join(","));
console.log(encoder.encodeInto("😀", new Uint8Array(3)));
console.log(failure(() => encoder.encodeInto("x", new Uint8ClampedArray(1) as any)));

const decoder = new TextDecoder(" \tUTF8\r", {fatal: true});
console.log(decoder.encoding, decoder.fatal, decoder.ignoreBOM);
console.log(decoder.decode(bytes), decoder.decode(bytes.buffer));
console.log(decoder.decode(new DataView(backing.buffer, 1, 7)));
console.log(decoder.decode(backing.subarray(1, 8), {stream: false}), decoder.decode().length);
const bom = new Uint8Array([0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, 65]);
const ignoring = new TextDecoder("utf-8", {ignoreBOM: true});
console.log(decoder.decode(bom).length, ignoring.ignoreBOM, ignoring.decode(bom).length);
const malformed = new Uint8Array([0xe2, 0x82, 65, 0xed, 0xa0, 0x80, 0xf0, 0x9f]);
console.log(new TextDecoder().decode(malformed));
console.log(failure(() => decoder.decode(malformed)), failure(() => decoder.decode("A" as any)));
console.log(failure(() => new TextDecoder("unsupported-label")));

const words = new Uint32Array(10);
const view = words.subarray(1, 9);
console.log(crypto.getRandomValues(view) === view, view.some(x => x !== 0), words[0], words[9]);
console.log(crypto.getRandomValues(new Uint16Array(32768)).byteLength);
console.log(failure(() => crypto.getRandomValues(new Uint16Array(32769))));
console.log(failure(() => crypto.getRandomValues(new Float32Array(1) as any)));
const uuid = crypto.randomUUID();
console.log(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid), uuid !== crypto.randomUUID());
console.log(failure(() => crypto.randomUUID.call({})));

const start = performance.now();
console.log(typeof start, Number.isFinite(start), start >= 0, performance.now() >= start);
console.log(failure(() => performance.now.call({})));

const binary = "\0Aéÿ";
console.log(btoa(binary), atob(btoa(binary)) === binary);
console.log(atob(" \tT\nWE\r") === "Ma", atob("TQ=="), atob(""), btoa(""));
console.log(failure(() => atob("A===")), failure(() => atob("AA-_")), failure(() => atob("TQ\v==")));
console.log(failure(() => btoa("Ā")), failure(() => btoa("😀")));
