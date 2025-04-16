import std::io;
import btree;

fn int compare_int(int a, int b) @inline
{
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

fn void main()
{
    BTree{int} set;
    set.init(mem);
    defer set.free();

    for (int i = 1; i <= 50_000_000; i++)
    {
        BTreeSlot{int} slot = set.@get_slot(; int item_from_tree, int* x)
        {
            *x = compare_int(i, item_from_tree);
        };
        *slot.item = i;
    }

    io::printfn("After insertion: %d", set.number_of_items);

    for (int i = 2; i <= 50_000_000; i += 2)
    {
        set.@remove(; int item_from_tree, int* x)
        {
            *x = compare_int(i, item_from_tree);
        };
    }

    io::printfn("After removal: %d", set.number_of_items);
}
