#include <stdint.h>
#include <stddef.h>

#ifndef __vita__
#error "__vita__ must be predefined by the Vita compiler"
#endif

#ifndef __ARM_EABI__
#error "Vita uses ARM EABI"
#endif

#ifndef __ARM_PCS_VFP
#error "Vita uses the hard-float procedure-call standard"
#endif

_Static_assert(sizeof(char) == 1, "unexpected char size");
_Static_assert((char)-1 < 0, "plain char must be signed");
_Static_assert(sizeof(short) == 2, "unexpected short size");
_Static_assert(sizeof(int) == 4, "unexpected int size");
_Static_assert(sizeof(long) == 4, "unexpected long size");
_Static_assert(sizeof(long long) == 8, "unexpected long long size");
_Static_assert(sizeof(void *) == 4, "unexpected pointer size");
_Static_assert(sizeof(size_t) == 4, "unexpected size_t size");

#define TYPES_COMPATIBLE(a, b) __builtin_types_compatible_p(a, b)
_Static_assert(TYPES_COMPATIBLE(int32_t, int), "int32_t must be int");
_Static_assert(TYPES_COMPATIBLE(uint32_t, unsigned int),
               "uint32_t must be unsigned int");

int main(void)
{
    return 0;
}
