/* Exercises all 23 functions covered by softfp-shim/ -- see run.sh, which
 * links this against the real stub archives (-lSceGxm_stub etc., exactly as
 * a package would) and checks the link map to confirm each one resolved to
 * the shim wrapper, not the raw hard-float stub. */

#include <psp2/gxm.h>
#include <psp2/motion.h>
#include <psp2/paf/graphics.h>
#include <psp2/paf/stdc.h>
#include <psp2/pgf.h>
#include <psp2/pvf.h>

void exercise_softfp_shims(void)
{
	SceGxmContext *context = 0;
	sceGxmSetViewport(context, 0.0f, 1.0f, 0.0f, 1.0f, 0.0f, 1.0f);
	sceGxmSetWClampValue(context, 1.0f);

	SceGxmDepthStencilSurface *surface = 0;
	sceGxmDepthStencilSurfaceSetBackgroundDepth(surface, 1.0f);
	(void)sceGxmDepthStencilSurfaceGetBackgroundDepth(surface);

	sceMotionSetAngleThreshold(1.0f);
	(void)sceMotionGetAngleThreshold();
	sceMotionRotateYaw(1.0f);

	scePafGraphicsUpdateCurrentWave(0, 1.0f);
	(void)sce_paf_strtod("1.5", 0);

	SceFontLibHandle libHandle = 0;
	unsigned int fontErrorCode = 0;
	sceFontSetResolution(libHandle, 1.0f, 1.0f);
	(void)sceFontPixelToPointH(libHandle, 1.0f, &fontErrorCode);
	(void)sceFontPixelToPointV(libHandle, 1.0f, &fontErrorCode);
	(void)sceFontPointToPixelH(libHandle, 1.0f, &fontErrorCode);
	(void)sceFontPointToPixelV(libHandle, 1.0f, &fontErrorCode);

	ScePvfLibId libID = 0;
	ScePvfFontId fontID = 0;
	ScePvfError pvfError = 0;
	scePvfSetCharSize(fontID, 1.0f, 1.0f);
	scePvfSetEM(libID, 1.0f);
	scePvfSetEmboldenRate(fontID, 1.0f);
	scePvfSetResolution(libID, 1.0f, 1.0f);
	scePvfSetSkewValue(fontID, 1.0f, 1.0f);
	(void)scePvfPixelToPointH(libID, 1.0f, &pvfError);
	(void)scePvfPixelToPointV(libID, 1.0f, &pvfError);
	(void)scePvfPointToPixelH(libID, 1.0f, &pvfError);
	(void)scePvfPointToPixelV(libID, 1.0f, &pvfError);
}

int main(void)
{
	exercise_softfp_shims();
	return 0;
}
