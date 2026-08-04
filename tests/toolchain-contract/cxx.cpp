#include <cstdint>
#include <type_traits>

#ifndef __vita__
#error "__vita__ must be predefined by the Vita compiler"
#endif

static_assert(std::is_signed_v<char>);
static_assert(std::is_same_v<std::int32_t, int>);
static_assert(std::is_same_v<std::uint32_t, unsigned int>);

struct base {
    virtual ~base() = default;
};

struct derived final : base {
};

static int exercise_exceptions_and_rtti()
{
    try {
        base *value = new derived;
        int result = dynamic_cast<derived *>(value) != nullptr ? 0 : 1;
        delete value;
        throw result;
    } catch (int result) {
        return result;
    }
}

int main()
{
    return exercise_exceptions_and_rtti();
}
