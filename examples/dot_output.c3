import std;

import btree;

fn int compare_ints(int a, int b)
{
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

fn void main()
{
    BTree{int} btree;
    btree.init(mem);

    for (int i = 0; i < 200; i++)
    {
        int elem = i * 10;
        BTreeSlot{int} slot;
        slot = btree.@get_slot(compare_ints, elem);
        *slot.item = elem;
    }
    // Insert items between existing items.
    for (int i = 0; i < 2000; i++)
    {
        int elem = i;
        BTreeSlot{int} slot;
        slot = btree.@get_slot(compare_ints, elem);
        *slot.item = elem;
    }

    btree.@to_dot(
        fn void?(OutStream out, int item_from_tree) { io::fprintf(out, "%d", item_from_tree)!; },
        io::stdout())!!;
}
