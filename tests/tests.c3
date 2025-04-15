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

fn void BTree{uint}.check_invariants_and_orderding(&self, usz expected_number_of_items)
{
    // Check invariants.
    assert(self.number_of_items == expected_number_of_items);

    self.check_invariants();

    // Check that items have correct order and their actual count.
    int actual_count;
    uint prev;
    self.@each(; uint* item_from_tree)
    {
        if (actual_count)
        {
            assert(prev < *item_from_tree);
        }
        actual_count++;
        prev = *item_from_tree;
    };
    assert(actual_count == expected_number_of_items);
}

fn void parametric_test(usz number_of_items_to_insert, usz min_expected_height)
{
    // TODO: Currently `BTree` doesn't have `free` so we use temp allocator.
    BTree{uint} btree;
    btree.init(mem);
    defer btree.free();

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

    assert(btree.root.height >= min_expected_height);
    btree.check_invariants_and_orderding(inserted);

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

    // Delete numbers.
    Sfc64Random r3;
    r3.set_seed(&entropy);
    usz deleted;

    for (int i; i < generated; i++)
    {
        uint number = r3.next_int();

        bool removed = btree.@remove(; item_from_tree, int* x)
        {
            *x = compare_uints(number, item_from_tree);
        };
        deleted += (usz)removed;

        // Several times during deletition check tree invariants.
        if (generated / 100 > 0 && i % (generated / 100) == 0)
        {
            btree.check_invariants_and_orderding(inserted - deleted);
        }
    }

    // Check empty tree.
    assert(deleted == inserted);
    assert(btree.root.height == 0);
    btree.check_invariants_and_orderding(0);
}

fn void test_small() @test
{
    // We want to create tree with at least 5 levels (height 4).
    // 20735 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11)
    // items can fit into tree with 4 levels. Having one more item guarantees at least 5 levels.
    for (int i; i < 100; i++)
    {
        parametric_test(20736, 4);
    }
}

fn void test_big() @test
{
    // We want to create tree with at least 8 levels (height 7).
    // 35831807 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11 + 12^4 * 11 + 12^5 * 11 + 12^6 * 11)
    // items can fit into tree with 7 levels. Having one more item guarantees at least 8 levels.
    for (int i; i < 4; i++)
    {
        parametric_test(35_831_808, 7);
    }
}

fn void test_bigger() @test
{
    parametric_test(90_000_000, 7);
}

// Needs 6 GB of memory.
// fn void test_huge() @test
// {
//     // We want to create tree with at least 8 levels.
//     // 429981695 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11 + 12^4 * 11 + 12^5 * 11 + 12^6 * 11 + 12^7 * 11)
//     // items can fit into tree with 7 levels. Having one more item guarantees at least 8 levels.
//     parametric_test(429_981_696, 8);
// }
