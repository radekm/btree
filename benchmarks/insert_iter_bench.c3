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
    @pool()
    {
        BTree{int} set;
        set.init(tmem);

        for (int i = 1; i <= 100_000_000; i++)
        {
            BTreeSlot{int} slot = set.@get_slot(&compare_int, i);
            *slot.item = i;
        }

        io::printfn("After insertion: %d", set.number_of_items);

        ulong sum;
        set.@each(; item_from_tree)
        {
            sum += (ulong)*item_from_tree;
        };

        io::printfn("Sum is: %d", sum);
    };  // `set` is freed here by `@pool`.
}
