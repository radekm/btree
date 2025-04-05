import std;
import btree;

fn int compare_uints(uint a, uint b)
{
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

// `OutStream` which throws everything away.
typedef Trash (OutStream) = uint;

fn usz? Trash.write(&self, char[] buffer) @dynamic
{
    return buffer.len;
}

fn void? Trash.write_byte(&self, char c) @dynamic
{
}

fn void parametric_insertion_test(usz number_of_items_to_insert, usz min_expected_height)
{
    // TODO: Currently `BTree` doesn't have `free` so we use temp allocator.
    @pool()
    {
        BTree{uint} btree;
        btree.init(tmem);

        char[8 * 4] entropy = random::entropy();
        Sfc64Random r;
        r.set_seed(&entropy);
        usz generated;
        usz inserted;

        while (inserted < number_of_items_to_insert)
        {
            uint new = r.next_int();
            generated++;

            BTreeSlot{uint} slot;
            slot = btree.@get_slot(; item_from_tree, int* x)
            {
                *x = compare_uints(new, item_from_tree);
            };

            // Only insert if the number wans't there before.
            if (!slot.existed)
            {
                *slot.item = new;
                inserted++;
            }
        }

        io::printfn("Generated %d, inserted %d", generated, inserted);

        // Check invariants.
        assert(btree.number_of_items == inserted);
        assert(btree.root.height >= min_expected_height);

        // `@to_dot` also check invariants.
        Trash trash;
        btree.@to_dot(&trash; uint item_from_tree)
        {
        }!!;

        // Check that items have correct order and their actual count.
        int actual_count;
        uint prev;
        btree.@each(; uint* item_from_tree)
        {
            if (actual_count)
            {
                assert(prev < *item_from_tree);
            }
            actual_count++;
            prev = *item_from_tree;
        };
        assert(actual_count == inserted);

        // Check that all numbers are in tree.
        Sfc64Random r2;
        r2.set_seed(&entropy);
        for (int i; i < generated; i++)
        {
            uint number = r2.next_int();

            BTreeSlot{uint} slot;
            slot = btree.@get_existing_slot(; item_from_tree, int* x)
            {
                *x = compare_uints(number, item_from_tree);
            };

            assert(slot.existed);
            assert(*slot.item == number);
        }
    };
}

fn void test_insertion_big() @test
{
    // We want to create tree with at least 7 levels.
    // 35831807 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11 + 12^4 * 11 + 12^5 * 11 + 12^6 * 11)
    // items can fit into tree with 6 levels. Having one more item guarantees at least 7 levels.
    for (int i; i < 10; i++)
    {
        parametric_insertion_test(35_831_808, 7);
    }
}

fn void test_insertion_bigger() @test
{
    parametric_insertion_test(90_000_000, 7);
}

// Needs 6 GB of memory.
// fn void test_insertion_huge() @test
// {
//     // We want to create tree with at least 8 levels.
//     // 429981695 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11 + 12^4 * 11 + 12^5 * 11 + 12^6 * 11 + 12^7 * 11)
//     // items can fit into tree with 7 levels. Having one more item guarantees at least 8 levels.
//     parametric_insertion_test(429_981_696, 8);
// }
