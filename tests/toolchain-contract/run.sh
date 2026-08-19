#!/usr/bin/env sh
set -eu

: "${VITASDK:?set VITASDK to the VitaSDK installation directory}"

CC="${VITASDK}/bin/arm-vita-eabi-gcc"
CXX="${VITASDK}/bin/arm-vita-eabi-g++"
READELF="${VITASDK}/bin/arm-vita-eabi-readelf"

for tool in "${CC}" "${CXX}" "${READELF}"; do
    if [ ! -x "${tool}" ]; then
        echo "missing tool: ${tool}" >&2
        exit 1
    fi
done

srcdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/vita-contract.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT HUP INT TERM

expect_text()
{
    haystack=$1
    needle=$2
    description=$3

    printf '%s\n' "${haystack}" | grep -F -- "${needle}" >/dev/null || {
        echo "missing ${description}: ${needle}" >&2
        exit 1
    }
}

reject_text()
{
    haystack=$1
    needle=$2
    description=$3

    if printf '%s\n' "${haystack}" | grep -F -- "${needle}" >/dev/null; then
        echo "unexpected ${description}: ${needle}" >&2
        exit 1
    fi
}

echo "checking predefined macros"
macros=$("${CC}" -dM -E -x c /dev/null)
expect_text "${macros}" "#define __vita__ 1" "__vita__ macro"
expect_text "${macros}" "#define __ARM_EABI__ 1" "ARM EABI macro"
expect_text "${macros}" "#define __ARM_ARCH 7" "ARMv7 default"
expect_text "${macros}" "#define __ARM_NEON 1" "NEON default"

echo "checking float ABI contract"
# The float ABI (hard vs softfp) is a build parameter (VITASDK_FLOAT_ABI):
# detect which one this compiler defaults to, then assert the contract for
# that world in both directions instead of assuming hard-float.
expect_text "${macros}" "#define __ARM_FP " \
    "hardware FPU macro (both float ABIs compute on VFP hardware)"
if printf '%s\n' "${macros}" | grep -qF '#define __ARM_PCS_VFP 1'; then
    float_abi=hard
else
    float_abi=softfp
fi
echo "detected float ABI: ${float_abi}"

if [ "${float_abi}" = "hard" ]; then
    expect_text "${macros}" "#define __ARM_PCS_VFP 1" "hard-float PCS macro"
else
    reject_text "${macros}" "#define __ARM_PCS_VFP 1" \
        "hard-float PCS macro in a softfp toolchain"
fi

echo "checking C ABI"
"${CC}" -std=c11 -Wall -Wextra -Werror -c \
    "${srcdir}/abi.c" -o "${workdir}/abi.o"

echo "checking ARM float ABI attribute"
abi_attributes=$("${READELF}" -A "${workdir}/abi.o")
if [ "${float_abi}" = "hard" ]; then
    expect_text "${abi_attributes}" "Tag_ABI_VFP_args" \
        "VFP-args ABI attribute in a hard-float object"
else
    reject_text "${abi_attributes}" "Tag_ABI_VFP_args" \
        "VFP-args ABI attribute in a softfp object"
fi

echo "checking C++ ABI, exceptions and RTTI"
"${CXX}" -std=c++17 -Wall -Wextra -Werror -c \
    "${srcdir}/cxx.cpp" -o "${workdir}/cxx.o"

echo "checking driver default libraries"
driver=$("${CC}" -### "${srcdir}/abi.c" -o "${workdir}/abi.elf" 2>&1 || true)

for library in \
    SceRtc_stub \
    SceSysmem_stub \
    SceKernelThreadMgr_stub \
    SceKernelModulemgr_stub \
    SceIofilemgr_stub \
    SceProcessmgr_stub \
    SceLibKernel_stub \
    SceNet_stub \
    SceNetCtl_stub \
    SceSysmodule_stub
do
    expect_text "${driver}" "-l${library}" "default Vita library"
done

echo "checking -pthread driver policy"
pthread_driver=$(
    "${CC}" -### -pthread "${srcdir}/abi.c" \
        -o "${workdir}/pthread.elf" 2>&1 || true
)
expect_text "${pthread_driver}" "--whole-archive" "pthread whole-archive start"
expect_text "${pthread_driver}" "-lpthread" "pthread library"
expect_text "${pthread_driver}" "--no-whole-archive" "pthread whole-archive end"

echo "checking standard driver suppression options"
nodefaultlibs=$(
    "${CC}" -### -nodefaultlibs "${srcdir}/abi.c" \
        -o "${workdir}/nodefaultlibs.elf" 2>&1 || true
)
reject_text "${nodefaultlibs}" "-lSceLibKernel_stub" \
    "Vita libraries with -nodefaultlibs"
reject_text "${nodefaultlibs}" "-lc" "libc with -nodefaultlibs"

nostdlib=$(
    "${CC}" -### -nostdlib "${srcdir}/abi.c" \
        -o "${workdir}/nostdlib.elf" 2>&1 || true
)
reject_text "${nostdlib}" "-lSceLibKernel_stub" \
    "Vita libraries with -nostdlib"
reject_text "${nostdlib}" "crt0" "startup files with -nostdlib"

echo "checking ARM unwind section generation"
"${CXX}" -std=c++17 -fexceptions -funwind-tables -c \
    "${srcdir}/unwind.cpp" -o "${workdir}/unwind.o"
"${READELF}" -SW "${workdir}/unwind.o" |
    grep -F '.ARM.exidx' >/dev/null || {
        echo "missing .ARM.exidx in exception-enabled C++ object" >&2
        exit 1
    }

echo "checking that public headers compile on their own"
"${srcdir}/self-contained-headers.sh"

if [ "${float_abi}" = "softfp" ]; then
    echo "checking the softfp ABI shims (23 functions) resolve against the shim, not the raw stub"
    shim_map="${workdir}/softfp-shim.map"
    "${CC}" -std=c11 -Wall -Wextra -Werror \
        "${srcdir}/softfp-shim.c" -o "${workdir}/softfp-shim.elf" \
        -lSceGxm_stub -lSceMotion_stub -lScePaf_stub -lScePgf_stub -lScePvf_stub \
        -Wl,-Map="${shim_map}"

    shim_map_text=$(cat "${shim_map}")
    for shimmed_function in \
        sceGxmSetViewport sceGxmSetWClampValue \
        sceGxmDepthStencilSurfaceSetBackgroundDepth \
        sceGxmDepthStencilSurfaceGetBackgroundDepth \
        sceMotionSetAngleThreshold sceMotionGetAngleThreshold sceMotionRotateYaw \
        scePafGraphicsUpdateCurrentWave sce_paf_strtod \
        sceFontSetResolution sceFontPixelToPointH sceFontPixelToPointV \
        sceFontPointToPixelH sceFontPointToPixelV \
        scePvfSetCharSize scePvfSetEM scePvfSetEmboldenRate scePvfSetResolution \
        scePvfSetSkewValue scePvfPixelToPointH scePvfPixelToPointV \
        scePvfPointToPixelH scePvfPointToPixelV
    do
        expect_text "${shim_map_text}" "(${shimmed_function}.o)" \
            "${shimmed_function} resolved against the softfp shim wrapper"
    done
fi

echo "Vita GCC/binutils contract OK"
