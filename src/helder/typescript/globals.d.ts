// Globals tshx provides beyond the ECMAScript library.
declare const console: { log(...values: any[]): void };
declare function setImmediate(callback: (...args: any[]) => void, ...args: any[]): number;
declare function clearImmediate(id: number | undefined): void;
declare function setTimeout(callback: (...args: any[]) => void, ms?: number, ...args: any[]): number;
declare function setInterval(callback: (...args: any[]) => void, ms?: number, ...args: any[]): number;
declare function clearTimeout(id: number | undefined): void;
declare function clearInterval(id: number | undefined): void;
declare function queueMicrotask(callback: () => void): void;
declare function structuredClone<T>(value: T): T;
interface TextEncoder {
	readonly encoding: "utf-8";
	encode(input?: string): Uint8Array<ArrayBuffer>;
	encodeInto(source: string, destination: Uint8Array<ArrayBuffer>): { read: number; written: number };
}
declare var TextEncoder: { prototype: TextEncoder; new(): TextEncoder };
interface TextDecoder {
	readonly encoding: "utf-8";
	readonly fatal: boolean;
	readonly ignoreBOM: boolean;
	decode(input?: ArrayBuffer | ArrayBufferView<ArrayBuffer>, options?: { stream?: boolean }): string;
}
declare var TextDecoder: {
	prototype: TextDecoder;
	new(label?: string, options?: { fatal?: boolean; ignoreBOM?: boolean }): TextDecoder;
};
declare var crypto: {
	getRandomValues<T extends Int8Array | Uint8Array | Uint8ClampedArray | Int16Array | Uint16Array | Int32Array | Uint32Array>(array: T): T;
	randomUUID(): string;
};
declare var performance: { now(): number };
declare function atob(data: string): string;
declare function btoa(data: string): string;
// (V8's, which node's types declare: an object's stack from here, and how many frames a stack keeps)
interface ErrorConstructor {
	captureStackTrace(target: object, constructorOpt?: Function): void;
	stackTraceLimit: number;
}
