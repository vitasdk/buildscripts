include_guard(GLOBAL)

# Published profile (world) names; describe rejects anything else.
set(VITASDK_PROFILES vita vita_softfp)

# The float ABI each profile bakes into the toolchain. A profile is a world and
# a world is named by the architecture its packages carry, so the name is the
# same on both sides of the build.
set(VITASDK_PROFILE_FLOAT_ABI_vita hard)
set(VITASDK_PROFILE_FLOAT_ABI_vita_softfp softfp)

# makepkg builds shell variable names from CARCH (depends_$CARCH), so a world
# whose name is not an identifier corrupts them and then aborts the build.
foreach(profile IN LISTS VITASDK_PROFILES)
    if(NOT profile MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
        message(FATAL_ERROR
            "profile '${profile}' is not a valid shell identifier; makepkg "
            "expands depends_${profile} and friends")
    endif()
endforeach()
