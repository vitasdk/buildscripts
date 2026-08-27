include_guard(GLOBAL)

# Published profile (world) names; describe rejects anything else.
set(VITASDK_PROFILES vita vita-softfp)

# The float ABI each profile bakes into the toolchain. A profile is a world and
# a world is named by the architecture its packages carry, so the name is the
# same on both sides of the build.
set(VITASDK_PROFILE_FLOAT_ABI_vita hard)
set(VITASDK_PROFILE_FLOAT_ABI_vita-softfp softfp)
