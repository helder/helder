#!/bin/sh
# helder.scene's frames (Scenes.hx) against <scene>.png, headless (RenderTest:
# Linux on Mesa's llvmpipe through an EGL pbuffer; macOS on Metal; Windows
# (RenderTest.exe) on D3D11's WARP, or on Linux under Wine: wined3d over
# llvmpipe, under Xvfb), as tests/gfx/check.sh.
#   sh tests/3d/check.sh <dir with RenderTest> [out dir]
set -e
bin=$1
out=${2:-$1}
here=$(dirname "$0")
export LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1
if [ -f "$bin/RenderTest.exe" ]; then
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) run() { "$bin/RenderTest.exe" "$@"; } ;;
	*)
		export WINEDEBUG=-all
		run() { sh "$here/../xvfb-run.sh" -a -s "-screen 0 640x480x24" "${WINE:-/usr/lib/wine/wine64}" "$bin/RenderTest.exe" "$@"; }
		;;
	esac
else
	run() { env -u DISPLAY "$bin/RenderTest" "$@"; }
	# (ARM64's llvmpipe: up to 3 levels from x86-64's, gfx's own frames too)
	case "$(uname -s)-$(uname -m)" in
	Linux-aarch64 | Linux-arm64) export HXMC_3D_TOLERANCE=3 ;;
	esac
fi
for s in gltf orbits shadows physics instances skin overlay textured packed spot sky lazy normals blend walker packedskin packednormals cascades environment morph chains packedmorph bloom normalgrid gpuparticles crystal khrtransform khrclearcoat compressed packedbc packedastc instancedmesh glow tsscene fog poststage unevenscale softshadows shading primitives toon sprites hemisphere prepass ssao dof tiltshift outline fxaa lut effects lines debugdraw helpers text3d ssr taa smaa motionblur godrays occlusion physical transmission khrspecular khriridescence khrvolume lights8 clustered spotshadow pointshadow shadowatlas lod sh probes arealight lightmap; do
	g=$s
	# (the packed sample draws the glTF one's frame, the lazy skin the skin's)
	[ $s = packed ] && g=gltf
	[ $s = lazy ] && g=skin
	[ $s = packedskin ] && g=skin
	[ $s = packednormals ] && g=normals
	[ $s = packedmorph ] && g=morph
	code=0
	# (SOFT=1, the CPU's back end: these two scenes' specular lobes and
	# clear coat sparkles land up to 9 levels from llvmpipe's goldens, as
	# Metal's do (151 at a sparkle): within 6 levels taken as equal)
	if [ -n "$SOFT" ] && { [ $s = khrclearcoat ] || [ $s = khrspecular ]; }; then
		(export HXMC_3D_TOLERANCE=6; run $s "$here/$g.png" "$out/$s.png") || code=$?
	else
		run $s "$here/$g.png" "$out/$s.png" || code=$?
	fi
	# (macOS without a Metal device: GfxTest's 3, skipped)
	[ $code = 3 ] && exit 0
	[ $code = 0 ] || exit $code
done
# (the compute paths' fallbacks, the same goldens: ClusteredLights' cells and
# InstanceCulling on the CPU, GL as a 3.0 context; the other back ends draw
# their compute paths again)
for s in clustered lod sh; do
	(export HELDER_NO_COMPUTE=1; run $s "$here/$s.png" "$out/$s-nocompute.png")
done
