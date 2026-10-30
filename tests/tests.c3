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

fn sz? Trash.write(&self, char[] buffer) @dynamic
{
    return buffer.len;
}

fn void? Trash.write_byte(&self, char c) @dynamic
{
}

fn void BTree{uint}.check_iteration_via_slot_api(&self)
{
    BTreeSlot{uint} slot = self.first_slot();

    self.@each(; uint* item_from_tree)
    {
        assert(slot.has_item());
        assert(slot.get() == *item_from_tree);
        assert(slot.existed);
        assert(slot.tree);
        if (slot.next())
        {
            assert(slot.prev());  // Reverse iteration must work too.
            assert(slot.get() == *item_from_tree);
            assert(slot.next());
        }
        else
        {
            // No next slot means `item_from_tree` is the last item.
            assert(self.last_item()!! == *item_from_tree);
        }
    };

    assert(!slot.has_item());
    assert(!slot.existed);
    assert(!slot.handle.node_ref.height);
    assert(!slot.handle.node_ref.node);
    assert(!slot.handle.item_idx);
    assert(!slot.tree);
}

fn void BTree{uint}.check_invariants_and_orderding(&self, sz expected_number_of_items)
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

macro void parametric_test(bool $prealloc, sz number_of_items_to_insert, sz min_expected_height)
{
    BTree{uint} btree;
    $if $prealloc:
        btree.init_try(mem)!!;
    $else
        btree.init(mem);
    $endif
    defer btree.free();

    char[8 * 4] entropy = random::entropy();
    Sfc64Random r;
    r.set_seed(&entropy);
    sz generated;
    sz inserted;

    while (inserted < number_of_items_to_insert)
    {
        uint new = r.next_int();
        generated++;

        BTreeSlot{uint} slot;
        $if $prealloc:
            slot = btree.@get_slot_try(compare_uints, new)!!;
        $else
            slot = btree.@get_slot(compare_uints, new);
        $endif

        // Only insert if the number wasn't there before.
        if (!slot.existed)
        {
            slot.set(new);
            inserted++;
        }
    }

    io::printfn("Generated %d, inserted %d", generated, inserted);

    assert(btree.root.height >= min_expected_height);
    btree.check_invariants_and_orderding(inserted);
    btree.check_iteration_via_slot_api();

    // Check that all numbers are in tree.
    Sfc64Random r2;
    r2.set_seed(&entropy);
    for (int i; i < generated; i++)
    {
        uint number = r2.next_int();

        BTreeSlot{uint} slot;
        slot = btree.@get_existing_slot(compare_uints, number);

        assert(slot.existed);
        assert(slot.get() == number);
    }

    // Delete numbers.
    Sfc64Random r3;
    r3.set_seed(&entropy);
    sz deleted;

    for (int i; i < generated; i++)
    {
        uint number = r3.next_int();

        bool removed = btree.@remove(compare_uints, number);
        deleted += (sz)removed;

        // Several times during deletition check tree invariants.
        if (generated / 100 > 0 && i % (generated / 100) == 0)
        {
            btree.check_invariants_and_orderding(inserted - deleted);
            btree.check_iteration_via_slot_api();
        }
    }

    // Check empty tree.
    assert(deleted == inserted);
    assert(btree.root.height == 0);
    btree.check_invariants_and_orderding(0);
    btree.check_iteration_via_slot_api();
}

fn void test_small() @test
{
    // We want to create tree with at least 5 levels (height 4).
    // 20735 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11)
    // items can fit into tree with 4 levels. Having one more item guarantees at least 5 levels.
    for (int i; i < 100; i++)
    {
        parametric_test(false, 20736, 4);
    }
}

fn void test_small_with_prealloc() @test
{
    // We want to create tree with at least 5 levels (height 4).
    // 20735 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11)
    // items can fit into tree with 4 levels. Having one more item guarantees at least 5 levels.
    for (int i; i < 100; i++)
    {
        parametric_test(true, 20736, 4);
    }
}

fn void test_big() @test
{
    // We want to create tree with at least 8 levels (height 7).
    // 35831807 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11 + 12^4 * 11 + 12^5 * 11 + 12^6 * 11)
    // items can fit into tree with 7 levels. Having one more item guarantees at least 8 levels.
    for (int i; i < 4; i++)
    {
        parametric_test(false, 35_831_808, 7);
    }
}

fn void test_big_with_prealloc() @test
{
    // We want to create tree with at least 8 levels (height 7).
    // 35831807 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11 + 12^4 * 11 + 12^5 * 11 + 12^6 * 11)
    // items can fit into tree with 7 levels. Having one more item guarantees at least 8 levels.
    for (int i; i < 4; i++)
    {
        parametric_test(true, 35_831_808, 7);
    }
}

fn void test_bigger() @test
{
    parametric_test(false, 90_000_000, 7);
}

// Needs 6 GB of memory.
// fn void test_huge() @test
// {
//     // We want to create tree with at least 9 levels (height 8).
//     // 429981695 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11 + 12^4 * 11 + 12^5 * 11 + 12^6 * 11 + 12^7 * 11)
//     // items can fit into tree with 8 levels. Having one more item guarantees at least 9 levels.
//     parametric_test(false, 429_981_696, 8);
// }

fn void parametric_test_for_remove_if(sz number_of_items_to_insert)
{
    BTree{uint} btree;
    btree.init(mem);
    defer btree.free();

    char[8 * 4] entropy = random::entropy();
    Sfc64Random r;
    r.set_seed(&entropy);
    sz generated;
    sz inserted;

    sz inserted_odd;
    while (inserted < number_of_items_to_insert)
    {
        uint new = r.next_int();
        generated++;

        BTreeSlot{uint} slot = btree.@get_slot(compare_uints, new);

        // Only insert if the number wans't there before.
        if (!slot.existed)
        {
            slot.set(new);
            inserted++;
            if (new % 2 == 1) inserted_odd++;
        }
    }

    io::printfn("Generated %d, inserted %d", generated, inserted);

    btree.check_invariants_and_orderding(inserted);
    btree.check_iteration_via_slot_api();

    // Delete even numbers.
    {
        Maybe{uint} last;
        btree.@remove_if(; uint* item_from_tree, bool* remove)
        {
            if (last.has_value)
            {
                assert(last.value < *item_from_tree);
            }
            last.set(*item_from_tree);

            *remove = *item_from_tree % 2 == 0;
        };
    }

    // Check tree.
    btree.check_invariants_and_orderding(inserted_odd);
    btree.check_iteration_via_slot_api();

    // Check that all odd numbers are in tree and even numbers aren't.
    Sfc64Random r2;
    r2.set_seed(&entropy);
    for (int i; i < generated; i++)
    {
        uint number = r2.next_int();

        BTreeSlot{uint} slot;
        slot = btree.@get_existing_slot(compare_uints, number);

        if (number % 2 == 0)
        {
            assert(!slot.existed);
            assert(!slot.has_item());
        }
        else
        {
            assert(slot.existed);
            assert(slot.has_item());
            assert(slot.get() == number);
        }
    }

    // Delete odd numbers.
    {
        Maybe{uint} last;
        btree.@remove_if(; uint* item_from_tree, bool* remove)
        {
            if (last.has_value)
            {
                assert(last.value < *item_from_tree);
            }
            last.set(*item_from_tree);

            *remove = *item_from_tree % 2 == 1;
        };
    }

    // Check empty tree.
    assert(btree.root.height == 0);
    btree.check_invariants_and_orderding(0);
    btree.check_iteration_via_slot_api();
}

fn void test_remove_if_small() @test
{
    // We want to create tree with at least 5 levels (height 4).
    // 20735 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11)
    // items can fit into tree with 4 levels. Having one more item guarantees at least 5 levels.
    for (int i; i < 100; i++)
    {
        parametric_test_for_remove_if(20736);
    }
}

macro void @parametric_test_remove_and_go(bool $go_to_next, sz number_of_items_to_insert)
{
    BTree{uint} btree;
    btree.init(mem);
    defer btree.free();

    char[8 * 4] entropy = random::entropy();
    Sfc64Random r;
    r.set_seed(&entropy);
    sz generated;

    List{uint} inserted;
    inserted.init(mem, initial_capacity: number_of_items_to_insert);
    defer inserted.free();

    while (inserted.len() < number_of_items_to_insert)
    {
        uint new = r.next_int();
        generated++;

        BTreeSlot{uint} slot = btree.@get_slot(compare_uints, new);

        // Only insert if the number wans't there before.
        if (!slot.existed)
        {
            slot.set(new);
            inserted.push(new);
        }
    }

    io::printfn("Generated %d, inserted %d", generated, inserted.len());

    btree.check_invariants_and_orderding(inserted.len());

    quicksort(&inserted);

    while (inserted.len() > 0)
    {
        sz idx = random::next(&r, (int)inserted.len());
        BTreeSlot{uint} slot = btree.@get_existing_slot(compare_uints, inserted[idx]);
        assert(slot.existed);
        assert(slot.has_item());
        assert(slot.get() == inserted[idx]);
        $if $go_to_next:
            bool another_item = slot.remove_and_go_to_next();
            sz another_idx = idx + 1;
        $else
            bool another_item = slot.remove_and_go_to_prev();
            sz another_idx = idx - 1;
        $endif
        if (another_item)
        {
            assert(slot.existed);
            assert(slot.has_item());
            assert(slot.get() == inserted[another_idx]);
        }
        else
        {
            assert(!slot.existed);
            assert(!slot.has_item());
            $if $go_to_next:
                assert(another_idx == inserted.len());
            $else
                assert(another_idx == -1);
            $endif
        }
        inserted.remove_at(idx);
    }

    // Check empty tree.
    assert(btree.root.height == 0);
    btree.check_invariants_and_orderding(0);
}

fn void test_remove_and_go_to_next_small() @test
{
    // We want to create tree with at least 5 levels (height 4).
    // 20735 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11)
    // items can fit into tree with 4 levels. Having one more item guarantees at least 5 levels.
    for (int i; i < 100; i++)
    {
        @parametric_test_remove_and_go(true, 20736);
    }
}

fn void test_remove_and_go_to_prev_small() @test
{
    // We want to create tree with at least 5 levels (height 4).
    // 20735 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11)
    // items can fit into tree with 4 levels. Having one more item guarantees at least 5 levels.
    for (int i; i < 100; i++)
    {
        @parametric_test_remove_and_go(false, 20736);
    }
}
