extern void sink(int);

__attribute__((noinline))
static void throw_value()
{
    throw 42;
}

int main()
{
    try {
        throw_value();
    } catch (int value) {
        sink(value);
    }
    return 0;
}
