package helder.media.windows;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
import helder.os.win32.Com;
import hxmc.unsafe.*;

// Media Foundation (mfplat.dll), loaded at run time: Windows' N editions
// and Server without its feature have none, and a program linking it would
// not start there. The decoders are its transforms (MFTs), driven directly:
// helder demuxes. Then the interfaces the decoders call (Com: a method is
// its vtable slot in the official headers' C vtables, the object first).
// HRESULTs are Int, times LONGLONG 100 ns units; GUIDs Ptr (REFGUID: a
// pointer), but by value to MFTEnumEx (MfGuid).
@:build(helder.os.Dl.build(true))
@:hxmc.unsafe(gc)
class Mf {
	static function MFStartup(version:Int, flags:Int):Int;
	static function MFCreateMediaType(out:Ptr<Ptr>):Int;
	static function MFCreateSample(out:Ptr<Ptr>):Int;
	static function MFCreateAlignedMemoryBuffer(max:Int, align:Int, out:Ptr<Ptr>):Int;
	static function MFTEnumEx(category:MfGuid, flags:Int, input:Ptr, output:Ptr, activates:Ptr<Ptr>, count:Ptr<Int32>):Int;
	static function MFCreateDXGIDeviceManager(token:Ptr<Int32>, out:Ptr<Ptr>):Int;

	static var tried = false;
	static var ok = false;

	// whether this Windows has Media Foundation, started (once, and COM on
	// this thread: the multithreaded apartment, or the one it is in already)
	public static function loaded():Bool {
		if (tried) return ok;
		tried = true;
		var why = load("mfplat.dll");
		if (why != null) {
			Sys.println('helder.media: no Media Foundation ($why)');
			return false;
		}
		helder.os.audio.Wasapi.Ole32.CoInitializeEx(Ptr.nil(), 0);
		// (MF_VERSION; MFSTARTUP_LITE: no sockets, the transforms alone)
		ok = MFStartup(0x20070, 1) >= 0;
		return ok;
	}

	// a GUID made of a FOURCC or a WAVE_FORMAT tag, as the media subtypes are
	public static function subtype(tag:Int):Ptr
		return Com.guid(tag, 0, 0x10, [0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71]);

	public static function fourcc(s:String):Int
		return s.charCodeAt(0) | s.charCodeAt(1) << 8 | s.charCodeAt(2) << 16 | s.charCodeAt(3) << 24;

	// (MFTEnumEx's flags: synchronous ones, local, sorted (the hardware's
	// asynchronous ones need an event loop of their own: Microsoft's
	// synchronous decoders use DXVA themselves, given a device manager))
	public static inline var ENUM = 0x1 | 0x10 | 0x40;
	public static inline var NEED_MORE_INPUT = 0xC00D6D72;
	public static inline var STREAM_CHANGE = 0xC00D6D61;
	public static inline var NOT_ACCEPTING = 0xC00D36B5;
	// (MFT_MESSAGE_TYPE)
	public static inline var FLUSH = 0;
	public static inline var DRAIN = 1;
	public static inline var SET_D3D_MANAGER = 2;
	public static inline var BEGIN_STREAMING = 0x10000000;
	public static inline var START_OF_STREAM = 0x10000003;
	// (MFT_OUTPUT_STREAM_INFO's flags: the transform gives its own samples)
	public static inline var PROVIDES_SAMPLES = 0x100;
	public static inline var CAN_PROVIDE_SAMPLES = 0x200;
}

@:hxmc.struct @:publicFields class MfGuid {
	var d1:UInt32;
	var d2:UInt16;
	var d3:UInt16;
	var d4:UInt32;
	var d5:UInt32;
}

// (the GUIDs the decoders use, as the headers write them)
@:hxmc.unsafe(gc)
class MfId {
	public static final VIDEO_DECODER = Com.guid(0xd6c02d4b, 0x6833, 0x45b4, [0x97, 0x1a, 0x05, 0xa4, 0xb0, 0x4b, 0xab, 0x91]);
	public static final AUDIO_DECODER = Com.guid(0x9ea73fb4, 0xef7a, 0x4559, [0x8d, 0x5d, 0x71, 0x9d, 0x8f, 0x04, 0x26, 0xc7]);
	public static final VIDEO = Mf.subtype(0x73646976);
	public static final AUDIO = Mf.subtype(0x73647561);
	public static final MAJOR_TYPE = Com.guid(0x48eba18e, 0xf8c9, 0x4687, [0xbf, 0x11, 0x0a, 0x74, 0xc9, 0xf9, 0x6a, 0x8f]);
	public static final SUBTYPE = Com.guid(0xf7e34c9a, 0x42e8, 0x4714, [0xb7, 0x4b, 0xcb, 0x29, 0xd7, 0x2c, 0x35, 0xe5]);
	public static final FRAME_SIZE = Com.guid(0x1652c33d, 0xd6b2, 0x4012, [0xb8, 0x34, 0x72, 0x03, 0x08, 0x49, 0xa3, 0x7d]);
	public static final DEFAULT_STRIDE = Com.guid(0x644b4e48, 0x1e02, 0x4516, [0xb0, 0xeb, 0xc0, 0x1c, 0xa9, 0xd4, 0x9a, 0xc6]);
	public static final INTERLACE_MODE = Com.guid(0xe2724bb8, 0xe676, 0x4806, [0xb4, 0xb2, 0xa8, 0xd6, 0xef, 0xb4, 0x4c, 0xcd]);
	public static final APERTURE = Com.guid(0xd7388766, 0x18fe, 0x48c6, [0xa1, 0x77, 0xee, 0x89, 0x48, 0x67, 0xc8, 0xc4]);
	public static final USER_DATA = Com.guid(0xb6bc765f, 0x4c3b, 0x40a4, [0xbd, 0x51, 0x25, 0x35, 0xb6, 0x6f, 0xe0, 0x9d]);
	public static final YUV_MATRIX = Com.guid(0x3e23d450, 0x2c75, 0x4d25, [0xa0, 0x0e, 0xb9, 0x16, 0x70, 0xd1, 0x23, 0x27]);
	public static final NOMINAL_RANGE = Com.guid(0xc21b8ee5, 0xb956, 0x4071, [0x8d, 0xaf, 0x32, 0x5e, 0xdf, 0x5c, 0xab, 0x11]);
	public static final CHANNELS = Com.guid(0x37e48bf5, 0x645e, 0x4c5b, [0x89, 0xde, 0xad, 0xa9, 0xe2, 0x9b, 0x69, 0x6a]);
	public static final RATE = Com.guid(0x5faeeae7, 0x0290, 0x4c31, [0x9e, 0x8a, 0xc5, 0x34, 0xf6, 0x8d, 0x9d, 0xba]);
	public static final BITS = Com.guid(0xf2deb57f, 0x40fa, 0x4764, [0xaa, 0x33, 0xed, 0x4f, 0x2d, 0x1f, 0xf6, 0x69]);
	public static final AAC_PAYLOAD = Com.guid(0xbfbabe79, 0x7434, 0x4d1c, [0x94, 0xf0, 0x72, 0xa3, 0xb9, 0xe1, 0x71, 0x88]);
	public static final D3D11_AWARE = Com.guid(0x206b4fc8, 0xfcf9, 0x4c51, [0xaf, 0xe3, 0x97, 0x64, 0x36, 0x9e, 0x33, 0xa0]);
	public static final LOW_LATENCY = Com.guid(0x9c27891a, 0xed7a, 0x40e1, [0x88, 0xe8, 0xb2, 0x27, 0x27, 0xa0, 0x24, 0xee]);
	public static final IMFTransform = Com.guid(0xbf94c121, 0x5b05, 0x4e6f, [0x80, 0x00, 0xba, 0x59, 0x61, 0x41, 0x4d, 0x34]);
	public static final IMF2DBuffer = Com.guid(0x7dc9d5f9, 0x9ed9, 0x44ec, [0x9b, 0xbf, 0x06, 0x00, 0xbb, 0x58, 0x9f, 0xbb]);
	public static final IMFDXGIBuffer = Com.guid(0xe7174cfa, 0x1c9e, 0x48b1, [0x88, 0x66, 0x62, 0x62, 0x26, 0xbf, 0xc2, 0x58]);
	public static final ID3D10Multithread = Com.guid(0x9b7e4e00, 0x342c, 0x4106, [0xa1, 0x9f, 0x4f, 0x27, 0x04, 0xf6, 0x89, 0xf0]);
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMFAttributes {
	@:slot(7) static function GetUINT32(self:Ptr, key:Ptr, out:Ptr<Int32>):Int;
	@:slot(8) static function GetUINT64(self:Ptr, key:Ptr, out:Ptr<Int64>):Int;
	@:slot(10) static function GetGUID(self:Ptr, key:Ptr, out:Ptr):Int;
	@:slot(15) static function GetBlob(self:Ptr, key:Ptr, out:Ptr, size:Int, got:Ptr<Int32>):Int;
	@:slot(21) static function SetUINT32(self:Ptr, key:Ptr, v:Int):Int;
	@:slot(22) static function SetUINT64(self:Ptr, key:Ptr, v:Int64):Int;
	@:slot(24) static function SetGUID(self:Ptr, key:Ptr, v:Ptr):Int;
	@:slot(26) static function SetBlob(self:Ptr, key:Ptr, data:Ptr, size:Int):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMFSample {
	@:slot(35) static function GetSampleTime(self:Ptr, out:Ptr<Int64>):Int;
	@:slot(36) static function SetSampleTime(self:Ptr, t:Int64):Int;
	@:slot(38) static function SetSampleDuration(self:Ptr, t:Int64):Int;
	@:slot(40) static function GetBufferByIndex(self:Ptr, i:Int, out:Ptr<Ptr>):Int;
	@:slot(41) static function ConvertToContiguousBuffer(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(42) static function AddBuffer(self:Ptr, b:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMFMediaBuffer {
	@:slot(3) static function Lock(self:Ptr, data:Ptr<Ptr>, max:Ptr<Int32>, current:Ptr<Int32>):Int;
	@:slot(4) static function Unlock(self:Ptr):Int;
	@:slot(5) static function GetCurrentLength(self:Ptr, out:Ptr<Int32>):Int;
	@:slot(6) static function SetCurrentLength(self:Ptr, n:Int):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMF2DBuffer {
	@:slot(3) static function Lock2D(self:Ptr, scan0:Ptr<Ptr>, pitch:Ptr<Int32>):Int;
	@:slot(4) static function Unlock2D(self:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMFDXGIBuffer {
	@:slot(3) static function GetResource(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
	@:slot(4) static function GetSubresourceIndex(self:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMFActivate {
	@:slot(33) static function ActivateObject(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMFDXGIDeviceManager {
	@:slot(7) static function ResetDevice(self:Ptr, device:Ptr, token:Int):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ID3D10Multithread {
	@:slot(5) static function SetMultithreadProtected(self:Ptr, on:Int):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IMFTransform {
	// (MFT_INPUT_STREAM_INFO and MFT_OUTPUT_STREAM_INFO: flags, size, alignment ...)
	@:slot(7) static function GetOutputStreamInfo(self:Ptr, stream:Int, info:Ptr<Int32>):Int;
	@:slot(8) static function GetAttributes(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(14) static function GetOutputAvailableType(self:Ptr, stream:Int, index:Int, out:Ptr<Ptr>):Int;
	@:slot(15) static function SetInputType(self:Ptr, stream:Int, type:Ptr, flags:Int):Int;
	@:slot(16) static function SetOutputType(self:Ptr, stream:Int, type:Ptr, flags:Int):Int;
	@:slot(18) static function GetOutputCurrentType(self:Ptr, stream:Int, out:Ptr<Ptr>):Int;
	@:slot(23) static function ProcessMessage(self:Ptr, message:Int, param:Ptr):Int;
	@:slot(24) static function ProcessInput(self:Ptr, stream:Int, sample:Ptr, flags:Int):Int;
	// (MFT_OUTPUT_DATA_BUFFER: the stream's id, its sample, status, events: 32 bytes)
	@:slot(25) static function ProcessOutput(self:Ptr, flags:Int, count:Int, buffers:Ptr, status:Ptr<Int32>):Int;
}
#end
