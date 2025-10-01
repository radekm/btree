import std;
import btree;

// Each allocation at first fails.
// It succeeds when retried.
struct MustRetryAllocator (Allocator) @local
{
    Allocator allocator;
    List{void*} free;
    usz ooms;
}

fn void MustRetryAllocator.init(&self, Allocator allocator) @local
{
    self.allocator = allocator;
    self.free.init(allocator);
}

// Doesn't check size. Instead it assumes that allocations are done in the same order when retried.
fn void*? MustRetryAllocator.acquire(&self, usz bytes, AllocInitType init_type, usz alignment) @dynamic @local
{
    void*? allocation = self.free.pop();
    if (catch allocation)
    {
        self.ooms++;
        void* ptr = self.allocator.acquire(bytes, init_type, alignment)!;
        self.free.push(ptr);
        return mem::OUT_OF_MEMORY?;
    }
    void* ptr = allocation;
    return ptr;
}

fn void*? MustRetryAllocator.resize(&self, void* old_ptr, usz new_bytes, usz alignment) @dynamic @local
{
    abort("Not supported");
}

fn void MustRetryAllocator.release(&self, void* old_ptr, bool aligned) @dynamic @local
{
    self.free.push(old_ptr);
}

fn int compare_uints(uint a, uint b)
{
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

fn void parametric_test_oom(usz number_of_items_to_insert, usz min_expected_height) => @pool()
{
    MustRetryAllocator allocator;
    allocator.init(tmem);

    BTree{uint} btree;
    while (true)
    {
        if (allocator.ooms > number_of_items_to_insert) abort("Too many OOMs");
        if (try btree.init_try(&allocator)) break;
    }

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
        while (true)
        {
            if (allocator.ooms > number_of_items_to_insert) abort("Too many OOMs");
            BTreeSlot{uint}? slot_or_excuse = btree.@get_slot_try(compare_uints, new);
            if (try slot_or_excuse)
            {
                slot = slot_or_excuse;
                break;
            }
        }

        // Only insert if the number wans't there before.
        if (!slot.existed)
        {
            *slot.item = new;
            inserted++;
        }
    }

    io::printfn("Generated %d, inserted %d, ooms %d", generated, inserted, allocator.ooms);

    assert(btree.root.height >= min_expected_height);
    btree.check_invariants_and_orderding(inserted);
}

fn void test_small_oom() @test
{
    // We want to create tree with at least 5 levels (height 4).
    // 20735 (= 12^0 * 11 + 12^1 * 11 + 12^2 * 11 + 12^3 * 11)
    // items can fit into tree with 4 levels. Having one more item guarantees at least 5 levels.
    for (int i; i < 100; i++)
    {
        parametric_test_oom(20736, 4);
    }
}
