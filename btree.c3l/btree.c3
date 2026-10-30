module btree <Type>;

import std::collections::maybe;
import std::io;

struct SearchResult
{
    bool found;
    union
    {
        HandleItem existing_item;
        HandleEdge insert_position;
    }
}

// `#compare` is a comparison function and `...` are arguments which are given to it first.
// Its last argument is an item from the tree.
// It returns value lower than zero if we search for something smaller than the item from the tree.
// It returns value higher than zero if we search for something bigger than the item from the tree.
// Otherwise the item from the tree is what we search for and `#comparison` returns zero.
//
// The most common usage is that `...` contains context needed for comparison
// and key we search for. In that case `#compare` is called as `#compare(ctx1, ctx2, ctx3, key, item_from_tree)`
// and `@search_tree` is called as
//
//     ```
//     node_ref.@search_tree(
//         fn int(Ctx1 ctx1, Ctx2 ctx2, Ctx3 ctx3, Key key, Type item_from_tree) {
//             // Code for comparison is here.
//         },
//         ctx1, ctx2, ctx3, key);
//     ```
macro SearchResult NodeRef.@search_tree(self, #compare, ...)
{
    NodeRef root = self;

    while (true)
    {
        LeafNode* node = root.node;

        int edge;
        for (; edge < node.len; edge++)
        {
            int x = #compare(...$vaarg, node.items[edge]);
            if (x < 0)
            {
                // We search for something smaller than `node.items[edge]`.
                // We have to go down if possible.
                break;
            }
            else if (x > 0)
            {
                // We search for something bigger than `node.items[edge]`.
                // Go to the right. At this point it is possible.
            }
            else
            {
                // We found what we searched for.
                SearchResult result;
                result.found = true;
                result.existing_item = {
                    .node_ref = root,
                    .item_idx = edge,
                };
                return result;
            }
        }

        // What we search for wasn't found in current `root`.
        // If we're in a leaf we return insert position.
        // Otherwise we go down.

        if (root.height == 0)
        {
            // We're in a leaf.
            SearchResult result;
            result.insert_position = {
                .node_ref = root,
                .edge_idx = edge,
            };
            return result;
        }

        // Go down.
        InternalNode* internal_node = (InternalNode*)node;
        root.height--;
        root.node = internal_node.edges[edge];
    }
}

struct BTree
{
    NodeRef root;
    Allocator allocator;
    sz number_of_items;
}

// If there's not enough memory this function will panic and B-tree won't be initialized.
fn void BTree.init(&self, Allocator allocator)
{
    LeafNode* node = alloc::new(allocator, LeafNode);
    *self = {
        .root = { .node = node },
        .allocator = allocator,
    };
}

// If there is not enough memory this function will return `mem::OUT_OF_MEMORY`
// and B-tree won't be initialized.
fn void? BTree.init_try(&self, Allocator allocator)
{
    LeafNode* node = alloc::new_try(allocator, LeafNode)!;
    *self = {
        .root = { .node = node },
        .allocator = allocator,
    };
}

// Slot points to an item in the tree or is empty (`has_item()` returns false).
// Any modification of the tree (insertion or removal) invalidates all slots
// except the one which was used to perform the modification.
struct BTreeSlot
{
    // Valid if the slot is not empty.
    HandleItem handle;
    // Non-null if the slot is not empty.
    // For removal we need both allocator and root.
    BTree* tree;
}

fn bool BTreeSlot.has_item(self) @inline => (bool)self.tree;
fn Type* BTreeSlot.get_ref(self) @inline => &self.handle.node_ref.node.items[self.handle.item_idx];
fn Type BTreeSlot.get(self) @inline => *self.get_ref();
fn void BTreeSlot.set(self, Type item) @inline => *self.get_ref() = item;
// Slot must not be used after calling `remove`.
fn void BTreeSlot.remove(&self) @inline
{
    self.handle.remove_item(&self.tree.root, self.tree.allocator);
    self.tree.number_of_items--;
    *self = {};
}

fn bool BTreeSlot.next(&self)
{
    if (handle_item_next_item(self.handle, &self.handle)) return true;

    // We walked the whole tree.
    *self = {};
    return false;
}

fn bool BTreeSlot.prev(&self)
{
    if (handle_item_prev_item(self.handle, &self.handle)) return true;

    // We walked the whole tree.
    *self = {};
    return false;
}

fn bool BTreeSlot.remove_and_go_to_next(&self)
{
    NodeRef* orig_root = &self.tree.root;
    Allocator allocator = self.tree.allocator;
    bool found_next;
    if (self.handle.node_ref.height == 0)
    {
        found_next = handle_edge_in_leaf_next_item(self.handle.remove_leaf_item(orig_root, allocator), &self.handle);
    }
    else
    {
        HandleItem predecessor;
        bool ok = true;
        ok &= handle_edge_in_leaf_next_item(self.handle.remove_internal_item(orig_root, allocator), &predecessor);
        ok &= handle_item_next_item(predecessor, &self.handle);
        // We were removing internal node. Every item in an internal node has both a predecessor and a successor,
        // so both `ok` and `found_next` must be true.
        assert(ok);
        found_next = true;
    }

    self.tree.number_of_items--;
    if (!found_next) *self = {};
    return found_next;
}

fn bool BTreeSlot.remove_and_go_to_prev(&self)
{
    NodeRef* orig_root = &self.tree.root;
    Allocator allocator = self.tree.allocator;
    bool found_prev;
    if (self.handle.node_ref.height == 0)
    {
        found_prev = handle_edge_in_leaf_prev_item(self.handle.remove_leaf_item(orig_root, allocator), &self.handle);
    }
    else
    {
        bool ok = handle_edge_in_leaf_next_item(self.handle.remove_internal_item(orig_root, allocator), &self.handle);
        // We were removing internal node. Every item in an internal node has both a predecessor and a successor,
        // so `ok` and `found_prev` must be true.
        assert(ok);
        found_prev = true;
    }

    self.tree.number_of_items--;
    if (!found_prev) *self = {};
    return found_prev;
}

// Finds an existing item. If the item is not found then the returned slot is empty.
macro BTreeSlot BTree.@get_slot(&self, #compare, ...)
{
    SearchResult sr = self.root.@search_tree(#compare, ...$vaarg);

    if (!sr.found)
    {
        return {};
    }
    else
    {
        return { .handle = sr.existing_item, .tree = self };
    }
}

// Finds an existing item or creates a new one. The returned slot is never empty.
// The new item is zeroed and the caller must immediately set it (via `set` or `get_ref`)
// to a value which is equal to the searched one (ie. `#compare` returns zero for it).
//
// If `created` is non-null then `*created` is set to true if a new item was created
// and to false if the item already existed. Since `created` follows variadic arguments
// it must be passed by name: `tree.@get_or_create_slot(cmp, key, created: &created)`.
//
// If there's not enough memory this function will panic.
macro BTreeSlot BTree.@get_or_create_slot(&self, #compare, ..., bool* created = null)
{
    SearchResult sr = self.root.@search_tree(#compare, ...$vaarg);

    HandleItem handle;
    if (sr.found)
    {
        handle = sr.existing_item;
    }
    else
    {
        handle = sr.insert_position.insert_into_leaf_recursing_up({}, &self.root, self.allocator);
        self.number_of_items++;
    }

    if (created) *created = !sr.found;
    return { .handle = handle, .tree = self };
}

struct Preallocator (Allocator) @local
{
    // B-tree with 2^128 nodes has height less than 64.
    // So we expect that ability to preallocate 64 nodes is enough.
    LeafNode*[64] preallocated;
    sz used;
}

<*
 @require number_of_new_nodes > 0
*>
fn void? Preallocator.init(&self, Allocator allocator, sz number_of_new_nodes)
{
    if (number_of_new_nodes > self.preallocated.len) return mem::OUT_OF_MEMORY~;

    bool done;

    // Free all nodes if preallocation fails.
    defer if (!done)
    {
        // Free in reverse order.
        foreach_r (node : self.preallocated)
        {
            if (node) alloc::free(allocator, node);
        }
    }

    // Insertion will start by splitting leaf and then continue with `number_of_new_nodes - 1` internal nodes.

    // Memory has to be zeroed because `PreAllocator.acquire`
    // ignores `init_type` and doesn't zero anything it.
    self.preallocated[0] = alloc::new_try(allocator, LeafNode)!;

    for (int i = 1; i < number_of_new_nodes; i++)
    {
        // Memory has to be zeroed.
        self.preallocated[i] = (LeafNode*)alloc::new_try(allocator, InternalNode)!;
    }
    done = true;  // Everything preallocated successfully.
}

fn void*? Preallocator.acquire(&self, sz bytes, AllocInitType init_type, sz alignment) @dynamic
{
    assert(init_type == ZERO);
    if (self.used == 0)
    {
        assert(bytes == LeafNode::size);
    }
    else
    {
        assert(bytes == InternalNode::size);
    }
    LeafNode* node = self.preallocated[self.used++];
    assert(node != null);
    return node;
}

fn void*? Preallocator.resize(&self, void* old_ptr, sz new_bytes, sz alignment) @dynamic
{
    abort("Not supported");
}

fn void Preallocator.release(&self, void* old_ptr, bool aligned) @dynamic
{
    abort("Not supported");
}

// Same as `@get_or_create_slot` but if there is not enough memory
// this function will return `mem::OUT_OF_MEMORY` and B-tree won't be changed
// (`*created` won't be changed either).
macro BTreeSlot? BTree.@get_or_create_slot_try(&self, #compare, ..., bool* created = null)
{
    SearchResult sr = self.root.@search_tree(#compare, ...$vaarg);

    HandleItem handle;
    if (sr.found)
    {
        handle = sr.existing_item;
    }
    else
    {
        // Count how many new nodes need to be allocated.
        sz number_of_new_nodes;
        {
            LeafNode* node = sr.insert_position.node_ref.node;
            while (true)
            {
                if (!node)
                {
                    // For new root.
                    number_of_new_nodes++;
                    break;
                }
                if (node.len < CAPACITY) break;
                number_of_new_nodes++;
                node = (LeafNode*)node.parent;
            }
        }

        if (number_of_new_nodes)
        {
            // Preallocate new nodes.
            Preallocator preallocator;
            preallocator.init(self.allocator, number_of_new_nodes)!;
            handle = sr.insert_position.insert_into_leaf_recursing_up({}, &self.root, &preallocator);
            assert(preallocator.used == number_of_new_nodes, "Preallocated nodes must be used");
        }
        else
        {
            // No allocations are needed.
            handle = sr.insert_position.insert_into_leaf_recursing_up({}, &self.root, &allocators::NULL_ALLOCATOR);
        }

        self.number_of_items++;
    }

    if (created) *created = !sr.found;
    return { .handle = handle, .tree = self };
}

macro bool BTree.@remove(&self, #compare, ...)
{
    SearchResult sr = self.root.@search_tree(#compare, ...$vaarg);

    if (!sr.found)
    {
        return false;
    }
    else
    {
        sr.existing_item.remove_item(&self.root, self.allocator);
        self.number_of_items--;
        return true;
    }
}

fn void BTree.free(&self)
{
    if (!self.root.node && !self.root.height && !self.allocator && !self.number_of_items) return;

    HandleEdge edge = { .node_ref = self.root };
    while (true)
    {
        // First go down using the current `edge`.
        if (edge.node_ref.height > 0)
        {
            InternalNode* internal_node = (InternalNode*)edge.node_ref.node;
            edge = {
                .node_ref = {
                    .height = edge.node_ref.height - 1,
                    .node = internal_node.edges[edge.edge_idx],
                },
            };
        }
        // If it's not possible to go down then go up until it's possible to go right.
        // This means that we may not go up at all and instead go right immediately.
        // If it's not possible to go right at any level then we have walked the whole tree.
        else
        {
            // While it's not possible to go right, go up and free the node we are leaving.
            while (edge.edge_idx >= edge.node_ref.node.len && edge.node_ref.node.parent)
            {
                LeafNode* node_to_free = edge.node_ref.node;
                edge = {
                    .node_ref = {
                        .height = edge.node_ref.height + 1,
                        .node = &node_to_free.parent.data,
                    },
                    .edge_idx = node_to_free.parent_edge_idx,
                };
                alloc::free(self.allocator, node_to_free);
            }

            if (edge.edge_idx < edge.node_ref.node.len)
            {
                // It's possible to go right.
                edge.edge_idx++;
            }
            else
            {
                // We walked the whole tree, we can free the root.
                alloc::free(self.allocator, self.root.node);
                *self = {};  // Zero everything.
                return;
            }
        }
    }
}

// TODO: Create a generalized `@each` which walks the tree from the given `HandleEdge`.
//       It would be nice to start walking through the tree at some `HandleEdge`
//       stop somewhere else (not necessarily at the end) and later resume walking where we stopped.
macro void BTree.@each(&self; @body(Type* item_from_tree))
{
    HandleEdge edge = { .node_ref = self.root };
    while (true)
    {
        // First go down using the current `edge`.
        if (edge.node_ref.height > 0)
        {
            InternalNode* internal_node = (InternalNode*)edge.node_ref.node;
            edge = {
                .node_ref = {
                    .height = edge.node_ref.height - 1,
                    .node = internal_node.edges[edge.edge_idx],
                },
            };
        }
        // If it's not possible to go down then go up until it's possible to go right.
        // This means that we may not go up at all and instead go right immediately.
        // If it's not possible to go right at some level then we have walked the whole tree.
        else
        {
            // While it's not possible to go right, go up.
            while (edge.edge_idx >= edge.node_ref.node.len && edge.node_ref.node.parent)
            {
                edge = {
                    .node_ref = {
                        .height = edge.node_ref.height + 1,
                        .node = &edge.node_ref.node.parent.data,
                    },
                    .edge_idx = edge.node_ref.node.parent_edge_idx,
                };
            }

            if (edge.edge_idx < edge.node_ref.node.len)
            {
                // It's possible to go right.
                @body(&edge.node_ref.node.items[edge.edge_idx]);
                edge.edge_idx++;
            }
            else
            {
                // We walked the whole tree.
                return;
            }
        }
    }
}

fn void? LeafNode.output_dot_node_id(&self, OutStream out)
{
    if (!self.parent)
    {
        io::fprint(out, "root")!;
    }
    else
    {
        io::fprint(out, "node")!;

        LeafNode* cur = self;
        while (cur.parent)
        {
            // Describes from root in reverse order.
            io::fprintf(out, "_%d", cur.parent_edge_idx)!;
            cur = &cur.parent.data;
        }
    }
}

macro void? NodeRef.@output_dot_node(self, #output_item, OutStream out, ...)
{
    sz width = self.height * 30 + 1;  // Higher node --> wider space for edges.
    self.node.output_dot_node_id(out)!;
    io::fprint(out, "[label = < <TABLE BORDER=\"1\" CELLBORDER=\"1\" CELLSPACING=\"0\"><TR>")!;
    io::fprintf(out, "<TD PORT=\"e0\" WIDTH=\"%d\"></TD>", width)!;  // First edge.
    foreach (i, item : self.node.items[:self.node.len])
    {
        io::fprint(out, "<TD>")!;
        #output_item(out, ...$vaarg, item)!;
        io::fprint(out, "</TD>")!;
        io::fprintf(out, "<TD PORT=\"e%d\" WIDTH=\"%d\"></TD>", i + 1, width)!; // Edge after `i`-th item.
    }
    io::fprintn(out, "</TR></TABLE> >];")!;
}

// `@body` outputs item from tree to `out`.
macro void? BTree.@to_dot(&self, #output_item, OutStream out, ...)
{
    if (!self.root.node) abort("Node is not initialized");
    if (self.root.node.len > CAPACITY) abort("Len is bigger than capacity");
    if (self.root.node.parent) abort("Root must have no parent");
    if (self.root.node.parent_edge_idx) abort("Root must have no parent edge");

    // Dot header.
    io::fprintn(out, "digraph g {")!;
    io::fprintn(out, "node[shape = plaintext];")!;

    // Output root.
    self.root.@output_dot_node(#output_item, out, ...$vaarg)!;

    HandleEdge edge = { .node_ref = self.root };
    while (true)
    {
        // First go down using the current `edge`.
        if (edge.node_ref.height > 0)
        {
            InternalNode* internal_node = (InternalNode*)edge.node_ref.node;
            sz edge_idx = edge.edge_idx;

            edge = {
                .node_ref = {
                    .height = edge.node_ref.height - 1,
                    .node = internal_node.edges[edge_idx],
                },
            };

            if (!edge.node_ref.node) abort("Node is not initialized");
            if (edge.node_ref.node.len > CAPACITY) abort("Len is bigger than capacity");
            if (edge.node_ref.node.len < MIN_LEN_AFTER_SPLIT) abort("Underfull node");
            if (edge.node_ref.node.parent != internal_node) abort("Inconsistent parent");
            if (edge.node_ref.node.parent_edge_idx != edge_idx) abort("Inconsistent parent_edge_idx");

            // Output node the first time we reach it from its parent.
            edge.node_ref.@output_dot_node(#output_item, out, ...$vaarg)!;

            // Output parent edge which we just used to reached the node.
            internal_node.data.output_dot_node_id(out)!;  // Parent node.
            io::fprintf(out, ":e%d -> ", edge_idx)!;
            edge.node_ref.node.output_dot_node_id(out)!;  // Child node.
            io::fprintn(out, ";")!;
        }
        // If it's not possible to go down then go up until it's possible to go right.
        // This means that we may not go up at all and instead go right immediately.
        // If it's not possible to go right at some level then we have walked the whole tree.
        else
        {
            // While it's not possible to go right, go up.
            while (edge.edge_idx >= edge.node_ref.node.len && edge.node_ref.node.parent)
            {
                edge = {
                    .node_ref = {
                        .height = edge.node_ref.height + 1,
                        .node = &edge.node_ref.node.parent.data,
                    },
                    .edge_idx = edge.node_ref.node.parent_edge_idx,
                };
            }

            if (edge.edge_idx < edge.node_ref.node.len)
            {
                // It's possible to go right.
                edge.edge_idx++;
            }
            else
            {
                // We walked the whole tree.
                io::fprintn(out, "}")!;  // Close dot header.
                return;
            }
        }
    }
}

// Checks same invariants as `@to_dot` but it's faster since it doesn't generate any output.
// Ordering isn't checked.
fn void BTree.check_invariants(&self)
{
    if (!self.root.node) abort("Node is not initialized");
    if (self.root.node.len > CAPACITY) abort("Len is bigger than capacity");
    if (self.root.node.parent) abort("Root must have no parent");
    if (self.root.node.parent_edge_idx) abort("Root must have no parent edge");

    HandleEdge edge = { .node_ref = self.root };
    while (true)
    {
        // First go down using the current `edge`.
        if (edge.node_ref.height > 0)
        {
            InternalNode* internal_node = (InternalNode*)edge.node_ref.node;
            sz edge_idx = edge.edge_idx;

            edge = {
                .node_ref = {
                    .height = edge.node_ref.height - 1,
                    .node = internal_node.edges[edge_idx],
                },
            };

            if (!edge.node_ref.node) abort("Node is not initialized");
            if (edge.node_ref.node.len > CAPACITY) abort("Len is bigger than capacity");
            if (edge.node_ref.node.len < MIN_LEN_AFTER_SPLIT) abort("Underfull node");
            if (edge.node_ref.node.parent != internal_node) abort("Inconsistent parent");
            if (edge.node_ref.node.parent_edge_idx != edge_idx) abort("Inconsistent parent_edge_idx");
        }
        // If it's not possible to go down then go up until it's possible to go right.
        // This means that we may not go up at all and instead go right immediately.
        // If it's not possible to go right at some level then we have walked the whole tree.
        else
        {
            // While it's not possible to go right, go up.
            while (edge.edge_idx >= edge.node_ref.node.len && edge.node_ref.node.parent)
            {
                edge = {
                    .node_ref = {
                        .height = edge.node_ref.height + 1,
                        .node = &edge.node_ref.node.parent.data,
                    },
                    .edge_idx = edge.node_ref.node.parent_edge_idx,
                };
            }

            if (edge.edge_idx < edge.node_ref.node.len)
            {
                // It's possible to go right.
                edge.edge_idx++;
            }
            else
            {
                // We walked the whole tree.
                return;
            }
        }
    }
}

fn BTreeSlot BTree.first_slot(&self)
{
    if (!self.number_of_items) return {};

    NodeRef node_ref = self.root;
    while (node_ref.height > 0)
    {
        InternalNode* internal_node = (InternalNode*)node_ref.node;
        // Use the leftmost edge to go down.
        node_ref = {
            .height = node_ref.height - 1,
            .node = internal_node.edges[0],
        };
    }

    return {
        .handle = {
            .node_ref = node_ref,
            .item_idx = 0,
        },
        .tree = self,
    };
}

fn Type? BTree.first_item(&self)
{
    BTreeSlot slot = self.first_slot();
    if (!slot.has_item()) return NOT_FOUND~;

    return slot.get();
}

fn BTreeSlot BTree.last_slot(&self)
{
    if (!self.number_of_items) return {};

    NodeRef node_ref = self.root;
    while (node_ref.height > 0)
    {
        InternalNode* internal_node = (InternalNode*)node_ref.node;
        // Use the rightmost edge to go down.
        node_ref = {
            .height = node_ref.height - 1,
            .node = internal_node.edges[internal_node.data.len],
        };
    }

    return {
        .handle = {
            .node_ref = node_ref,
            .item_idx = (sz)node_ref.node.len - 1,
        },
        .tree = self,
    };
}

fn Type? BTree.last_item(&self)
{
    BTreeSlot slot = self.last_slot();
    if (!slot.has_item()) return NOT_FOUND~;

    return slot.get();
}

macro void BTree.@remove_if(&self; @body(Type* item_from_tree, bool* remove))
{
    BTreeSlot slot = self.first_slot();
    while (slot.has_item())
    {
        bool remove;
        @body(slot.get_ref(), &remove);
        if (remove)
        {
            slot.remove_and_go_to_next();
        }
        else
        {
            slot.next();
        }
    }
}
