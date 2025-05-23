import std;
import libc;

import btree;

struct Item
{
    String k;
    int v;
}

fn int compare_strings(String a, String b)
{
    int res = libc::memcmp(a.ptr, b.ptr, min(a.len, b.len));
    if (res < 0) return -1;
    if (res > 0) return 1;
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

fn void main()
{
    BTree{Item} btree;
    btree.init(mem);

    BTreeSlot{Item} slot;
    slot = btree.@get_slot(fn int(Item item_from_tree) => compare_strings("nose", item_from_tree.k));
    *slot.item = { .k = "nose", .v = 12 };

    slot = btree.@get_slot(fn int(Item item_from_tree) => compare_strings("mouth", item_from_tree.k));
    *slot.item = { .k = "mouth", .v = 13 };

    slot = btree.@get_slot(fn int(Item item_from_tree) => compare_strings("arm", item_from_tree.k));
    *slot.item = { .k = "arm", .v = 7 };

    // Item modification.
    // We can replace an item with an equivalent one
    // (for example we can replace a key with the same string which is allocated elsewhere).
    slot = btree.@get_existing_slot(fn int(Item item_from_tree) => compare_strings("mouth", item_from_tree.k));
    slot.item.v = -1;

    io::printfn("root length %s", btree.root.node.len);
    btree.@each(; item_from_tree)
    {
        io::printfn("item %s -> %s", item_from_tree.k, item_from_tree.v);
    };
}
