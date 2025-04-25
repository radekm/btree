import std::collections;
import std::io;

fn void main()
{
    HashMap{int, bool} set;  // Unfortunately we can't have `void` values.
    set.init(mem);
    defer set.free();

    for (int i = 1; i <= 50_000_000; i++)
    {
        set[i] = true;
    }

    io::printfn("After insertion: %d", set.len());

    for (int i = 2; i <= 50_000_000; i += 2)
    {
        set.remove(i);
    }

    io::printfn("After removal: %d", set.len());
}
