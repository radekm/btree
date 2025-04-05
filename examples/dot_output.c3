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
        slot = btree.@get_slot(; item_from_tree, int* x)
        {
            *x = compare_ints(elem, item_from_tree);
        };
        *slot.item = elem;
    }
    // Insert items between existing items.
    for (int i = 0; i < 2000; i++)
    {
        int elem = i;
        BTreeSlot{int} slot;
        slot = btree.@get_slot(; item_from_tree, int* x)
        {
            *x = compare_ints(elem, item_from_tree);
        };
        *slot.item = elem;
    }

    btree.@to_dot(io::stdout(); item_from_tree)
    {
        io::printf("%d", item_from_tree)!!;
    }!!;
}
