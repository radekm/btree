# API reference

This document describes the public API of the `btree` library (`btree.c3l`).
Everything not mentioned here (nodes, handles, `@search_tree` etc.) is an implementation detail
and may change without notice.

```c3
import btree;
```

## Contents

- [Overview](#overview)
- [Item type](#item-type)
- [Comparison function](#comparison-function)
- [Lifecycle](#lifecycle)
- [Slots](#slots)
- [Finding and inserting items](#finding-and-inserting-items)
- [Removing items](#removing-items)
- [Iteration](#iteration)
- [Number of items](#number-of-items)
- [Out of memory](#out-of-memory)
- [Debugging helpers](#debugging-helpers)
- [Rules to keep the tree valid](#rules-to-keep-the-tree-valid)
- [Quick reference](#quick-reference)

## Overview

`BTree{Type}` is an ordered collection of items of type `Type`.
The tree doesn't know how items are ordered. Instead, every operation which searches the tree
takes a comparison function. This makes it possible to store items whose key lives
somewhere else (for example handles into a pool) and to build several indices with different
orderings over the same data.

Items are accessed through `BTreeSlot{Type}`, a lightweight cursor which points to a single item
in the tree (or is empty). A slot can read, overwrite or remove its item and move to the next or
previous item.

```c3
import std;
import btree;

fn int compare_ints(int key, int item_from_tree)
{
    if (key < item_from_tree) return -1;
    if (key > item_from_tree) return 1;
    return 0;
}

fn void main()
{
    BTree{int} tree;
    tree.init(mem);
    defer tree.free();

    // Insert (or overwrite) items.
    foreach (int x : { 30, 10, 20 })
    {
        tree.@get_or_create_slot(compare_ints, x).set(x);
    }

    // Find an item.
    BTreeSlot{int} slot = tree.@get_slot(compare_ints, 20);
    if (slot.has_item()) io::printfn("found %d", slot.get());

    // Remove an item.
    tree.@remove(compare_ints, 10);

    // Iterate in ascending order.
    tree.@each(; int* item) { io::printfn("%d", *item); };
}
```

## Item type

Items are stored by value directly inside the nodes of the tree. A node holds up to 11 items,
and items are moved around all the time: when an item is inserted or removed, the following items
in the node are shifted, and when nodes are split, merged or rebalanced, items are copied between nodes.
Searching scans the items of each visited node and passes them to the comparison function by value.

**Therefore `Type` should be small.** Up to about 32 bytes works well
(integers, small structs, pointers, handles, `String` slices).

If your items are bigger, store them elsewhere (for example in a pool or an array) and put only
a handle or a pointer into the tree. The comparison function then receives the context
(the pool) as an extra argument and looks the item up. This is also how you build several indices
over the same data - see [`examples/order_book.c3`](../examples/order_book.c3).

## Comparison function

`@get_slot`, `@get_or_create_slot`, `@get_or_create_slot_try` and `@remove` take a comparison
function `#compare` followed by any number of arguments. The arguments are passed to `#compare`
first and the item from the tree is always passed last:

```c3
#compare(arg1, arg2, ..., item_from_tree)
```

`#compare` must return an `int`:

- a negative value if what we search for is **less** than `item_from_tree`,
- a positive value if what we search for is **greater** than `item_from_tree`,
- zero if `item_from_tree` is what we search for.

`#compare` may be a function, a function pointer or a lambda. Typically the arguments are
a context needed for comparison followed by the key:

```c3
// Items are handles into a pool, the key is an order id.
BTreeSlot{OrderHandle} slot = orders_by_id.@get_slot(
    fn int(Pool{Order}* orders, OrderId order_id, OrderHandle item_from_tree) {
        return compare_order_id(order_id, orders.get_ref(item_from_tree).order_id);
    },
    &pool, order_id);
```

The comparison must be consistent with the order of the items already in the tree:
use the same ordering for all operations on one tree.

## Lifecycle

| Function | Description |
|---|---|
| `void BTree.init(&self, Allocator allocator)` | Initializes an empty tree. Allocates the root node. Panics if there's not enough memory. |
| `void? BTree.init_try(&self, Allocator allocator)` | Same as `init` but returns `mem::OUT_OF_MEMORY` if there's not enough memory. The tree then stays uninitialized. |
| `void BTree.free(&self)` | Frees all nodes and zeroes the tree. |

- A zeroed `BTree` (for example a freshly declared variable) is **uninitialized**.
  All functions and macros except `init`, `init_try` and `free` require an initialized tree.
- `init` and `init_try` require an uninitialized tree. Calling `init` twice is a contract violation
  (it would leak the root node).
- `free` may be called on an uninitialized tree; it does nothing. After `free` the tree is
  uninitialized again and may be initialized once more.
- The tree doesn't own the items in any sense: `free` only frees the nodes. If items point
  to memory which needs freeing, free it before freeing the tree (for example with `@each`).

Contract violations are reported with messages `B-tree is not initialized`
and `B-tree is already initialized` (in builds where contracts are checked).

## Slots

`BTreeSlot{Type}` points to an item in the tree or is empty.

| Method | Description |
|---|---|
| `bool has_item()` | `true` if the slot points to an item. |
| `Type get()` | Returns a copy of the item. |
| `Type* get_ref()` | Returns a pointer to the item inside the tree. |
| `void set(Type item)` | Overwrites the item. |
| `void remove()` | Removes the item from the tree. The slot becomes empty. |
| `bool next()` | Moves to the next item. Returns `false` and makes the slot empty if there's none. |
| `bool prev()` | Moves to the previous item. Returns `false` and makes the slot empty if there's none. |
| `bool remove_and_go_to_next()` | Removes the item and moves to the next item. Returns `false` and makes the slot empty if there's none. |
| `bool remove_and_go_to_prev()` | Removes the item and moves to the previous item. Returns `false` and makes the slot empty if there's none. |

All methods except `has_item` require a non-empty slot (violation is reported
as `Slot is empty`).

**Slot invalidation.** Any insertion into the tree or removal from the tree invalidates all slots
of that tree except the slot which was used to perform the modification. Using an invalidated slot
is undefined behaviour and is *not* detected - typically it reads or overwrites a different item.
The same holds for pointers returned by `get_ref`. Obtain a new slot after inserting or removing items.
Modifying items (via `set` or `get_ref`) doesn't invalidate any slots.

**Keeping order.** Items may be freely modified through `set` or `get_ref` as long as each item
stays between its neighbours - it must remain greater than the item before it and less than
the item after it. For example it's fine to change data which doesn't take part in comparison,
to replace an item with an equal one (for example the same string allocated elsewhere),
or even to change the key, if the new key still falls between the neighbouring keys.

## Finding and inserting items

### `@get_slot`

```c3
macro BTreeSlot BTree.@get_slot(&self, #compare, ...)
```

Finds an existing item. If no item compares equal, the returned slot is empty. Never inserts or removes items.

```c3
BTreeSlot{Item} slot = tree.@get_slot(compare_items, key);
if (slot.has_item())
{
    slot.get_ref().counter++;  // Modify data which isn't part of the key.
}
```

### `@get_or_create_slot`

```c3
macro BTreeSlot BTree.@get_or_create_slot(&self, #compare, ..., bool* created = null)
```

Finds an existing item or inserts a new one at the position where the search ended.
The returned slot is never empty.

A newly inserted item is **zeroed**. The caller must immediately set it (via `set` or `get_ref`)
to a value which keeps the tree ordered - the value must be greater than the item before it and
less than the item after it. A value for which `#compare` returns zero always satisfies this.
Until the item is set, the tree contains a zero item at that position, so don't search the tree
in between.

`created` is optional. If it's given, `*created` is set to `true` when a new item was inserted
and to `false` when the item already existed. Because it follows the variadic arguments it must
be passed by name:

```c3
// Insert or overwrite.
tree.@get_or_create_slot(compare_items, key).set(item);

// Insert only if not present.
bool created;
BTreeSlot{Item} slot = tree.@get_or_create_slot(compare_items, key, created: &created);
if (created) slot.set(item);
```

Panics if there's not enough memory to split nodes.

### `@get_or_create_slot_try`

```c3
macro BTreeSlot? BTree.@get_or_create_slot_try(&self, #compare, ..., bool* created = null)
```

Same as `@get_or_create_slot` but returns `mem::OUT_OF_MEMORY` if there's not enough memory.
See [Out of memory](#out-of-memory).

## Removing items

### `@remove`

```c3
macro bool BTree.@remove(&self, #compare, ...)
```

Removes the item which compares equal. Returns `true` if an item was removed and `false`
if it wasn't found.

If you need the removed item, find it with `@get_slot`, read it and remove it through the slot:

```c3
BTreeSlot{Item} slot = tree.@get_slot(compare_items, key);
if (slot.has_item())
{
    Item item = slot.get();
    slot.remove();
}
```

### Removing while iterating

Use `remove_and_go_to_next` / `remove_and_go_to_prev` on a slot, or `@remove_if`:

```c3
macro void BTree.@remove_if(&self; @body(Type* item_from_tree, bool* remove))
```

Calls `@body` for each item in ascending order and removes the item if `@body` sets `*remove`
to `true`. `@body` may freely modify the item as long as it stays between its neighbours
(see [Keeping order](#slots)). `@body` must not insert into or remove from the tree by other means.

```c3
// Remove all even numbers.
tree.@remove_if(; int* item, bool* remove) { *remove = *item % 2 == 0; };
```

## Iteration

| Function | Description |
|---|---|
| `BTreeSlot BTree.first_slot(&self)` | Slot pointing to the smallest item. Empty if the tree is empty. |
| `BTreeSlot BTree.last_slot(&self)` | Slot pointing to the biggest item. Empty if the tree is empty. |
| `Type? BTree.first_item(&self)` | The smallest item or `NOT_FOUND` if the tree is empty. |
| `Type? BTree.last_item(&self)` | The biggest item or `NOT_FOUND` if the tree is empty. |
| `macro void BTree.@each(&self; @body(Type* item_from_tree))` | Calls `@body` for each item in ascending order. |

Iterating with a slot:

```c3
// Ascending.
for (BTreeSlot{int} slot = tree.first_slot(); slot.has_item(); slot.next())
{
    io::printn(slot.get());
}

// Descending.
for (BTreeSlot{int} slot = tree.last_slot(); slot.has_item(); slot.prev())
{
    io::printn(slot.get());
}
```

`@each` is the fastest way to visit all items. `@body` may freely modify the item as long as it
stays between its neighbours (see [Keeping order](#slots)). `@body` must not insert into or remove
from the tree.

There's currently no way to start iteration at the first item greater than or equal to a key
(lower bound) without inserting it.

## Number of items

`BTree.number_of_items` holds the number of items in the tree. Treat it as read-only.

## Out of memory

`init` and `@get_or_create_slot` panic when the allocator fails. Their counterparts `init_try` and
`@get_or_create_slot_try` instead return the allocator's error and leave the tree (and `*created`)
unchanged, so the tree may be used normally after a failure:

```c3
BTreeSlot{int}? slot = tree.@get_or_create_slot_try(compare_ints, x, created: &created);
if (catch err = slot)
{
    // Tree is unchanged, handle the error.
}
```

`@get_or_create_slot_try` preallocates all nodes the insertion may need before changing the tree.

Removal never allocates.

### Pattern: insertion which may fail

Often the item itself needs memory too (for example a copy of a string key), and that allocation
can only happen after the slot was created. If it fails, remove the newly created item through
the slot. Removal never allocates, so this rollback can't fail and the tree ends up
exactly as it was before:

```c3
struct Item
{
    String name;
    int value;
}

fn int compare_items(String name, Item item_from_tree) => name.compare_to(item_from_tree.name);

// Inserts a copy of `name` or updates the value of an existing item.
// If there's not enough memory the tree stays unchanged.
fn void? put(BTree{Item}* tree, Allocator allocator, String name, int value)
{
    bool created;
    BTreeSlot{Item} slot = tree.@get_or_create_slot_try(compare_items, name, created: &created)!;
    if (created)
    {
        // The tree now contains a zeroed item. Don't search the tree until it's set or removed.
        char[]? copy = alloc::new_array_try(allocator, char, name.len);
        if (catch err = copy)
        {
            slot.remove();  // The tree is the same as before the call.
            return err~;
        }
        copy[..] = name[..];
        slot.set({ .name = (String)copy, .value = value });
    }
    else
    {
        slot.get_ref().value = value;
    }
}
```

Removing the zeroed item is safe because removal through a slot doesn't call
the comparison function. The same pattern works for any other fallible step
which has to happen between creating and setting the item.

## Debugging helpers

| Function | Description |
|---|---|
| `void BTree.check_invariants(&self)` | Aborts if the structure of the tree is broken (node sizes, parent links). Doesn't check ordering of items. |
| `macro void? BTree.@to_dot(&self, #output_item, OutStream out, ...)` | Checks the same invariants and writes the tree in Graphviz DOT format to `out`. `#output_item` is called as `#output_item(out, ..., item_from_tree)` and writes one item. |

```c3
tree.@to_dot(
    fn void?(OutStream out, int item_from_tree) { io::fprintf(out, "%d", item_from_tree)!; },
    io::stdout())!!;
```

## Rules to keep the tree valid

These mistakes are not detected and silently corrupt the tree or your data:

1. **Set a newly created item immediately** to a value which fits between its neighbours.
2. **Keep every modified item between its neighbours** when modifying it through `set`, `get_ref`,
   `@each` or `@remove_if`.
3. **Use the same ordering** for all operations on one tree.
4. **Don't use slots or `get_ref` pointers after inserting or removing items** (except the slot
   used for the modification).
5. **Don't insert or remove items inside `@each`**, and inside `@remove_if` remove items only
   through `*remove`. Modifying the items themselves is fine (see rule 2).

These mistakes are reported by contracts (in builds where contracts are checked):

- using a tree before `init` or calling `init` twice,
- calling slot methods on an empty slot.

## Quick reference

```c3
// Lifecycle
fn void  BTree.init(&self, Allocator allocator);
fn void? BTree.init_try(&self, Allocator allocator);
fn void  BTree.free(&self);
sz       BTree.number_of_items;  // read-only

// Finding, inserting, removing
macro BTreeSlot  BTree.@get_slot(&self, #compare, ...);
macro BTreeSlot  BTree.@get_or_create_slot(&self, #compare, ..., bool* created = null);
macro BTreeSlot? BTree.@get_or_create_slot_try(&self, #compare, ..., bool* created = null);
macro bool       BTree.@remove(&self, #compare, ...);
macro void       BTree.@remove_if(&self; @body(Type* item_from_tree, bool* remove));

// Iteration
fn BTreeSlot BTree.first_slot(&self);
fn BTreeSlot BTree.last_slot(&self);
fn Type?     BTree.first_item(&self);
fn Type?     BTree.last_item(&self);
macro void   BTree.@each(&self; @body(Type* item_from_tree));

// Slot
fn bool  BTreeSlot.has_item(self);
fn Type  BTreeSlot.get(self);
fn Type* BTreeSlot.get_ref(self);
fn void  BTreeSlot.set(self, Type item);
fn void  BTreeSlot.remove(&self);
fn bool  BTreeSlot.next(&self);
fn bool  BTreeSlot.prev(&self);
fn bool  BTreeSlot.remove_and_go_to_next(&self);
fn bool  BTreeSlot.remove_and_go_to_prev(&self);

// Debugging
fn void      BTree.check_invariants(&self);
macro void?  BTree.@to_dot(&self, #output_item, OutStream out, ...);
```
