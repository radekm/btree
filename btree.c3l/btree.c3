module btree{Type};

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
            int x = #compare($vasplat, node.items[edge]);
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
    usz number_of_items;
}

fn void BTree.init(&self, Allocator allocator)
{
    *self = {
        .root = { .node = allocator::new(allocator, LeafNode) },
        .allocator = allocator,
    };
}

struct BTreeSlot
{
    bool existed;
    Type* item;
}

// CONSIDER: Return `Type*?` instead?
macro BTreeSlot BTree.@get_existing_slot(&self, #compare, ...)
{
    SearchResult sr = self.root.@search_tree(#compare, $vasplat);

    if (!sr.found)
    {
        return {};
    }
    else
    {
        LeafNode* node = sr.existing_item.node_ref.node;
        return { .existed = true, .item = &node.items[sr.existing_item.item_idx] };
    }
}

macro BTreeSlot BTree.@get_slot(&self, #compare, ...)
{
    SearchResult sr = self.root.@search_tree(#compare, $vasplat);

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

    LeafNode* node = handle.node_ref.node;
    return { .existed = sr.found, .item = &node.items[handle.item_idx] };
}

macro bool BTree.@remove(&self, #compare, ...)
{
    SearchResult sr = self.root.@search_tree(#compare, $vasplat);

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
                allocator::free(self.allocator, node_to_free);
            }

            if (edge.edge_idx < edge.node_ref.node.len)
            {
                // It's possible to go right.
                edge.edge_idx++;
            }
            else
            {
                // We walked the whole tree, we can free the root.
                allocator::free(self.allocator, self.root.node);
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

fn void? LeafNode.output_dot_node_id(&self, OutStream out) @local
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

macro void? NodeRef.@output_dot_node(self, #output_item, OutStream out, ...) @local
{
    usz width = self.height * 30 + 1;  // Higher node --> wider space for edges.
    self.node.output_dot_node_id(out)!;
    io::fprint(out, "[label = < <TABLE BORDER=\"1\" CELLBORDER=\"1\" CELLSPACING=\"0\"><TR>")!;
    io::fprintf(out, "<TD PORT=\"e0\" WIDTH=\"%d\"></TD>", width)!;  // First edge.
    foreach (i, item : self.node.items[:self.node.len])
    {
        io::fprint(out, "<TD>")!;
        #output_item(out, $vasplat, item)!;
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
    self.root.@output_dot_node(#output_item, out, $vasplat)!;

    HandleEdge edge = { .node_ref = self.root };
    while (true)
    {
        // First go down using the current `edge`.
        if (edge.node_ref.height > 0)
        {
            InternalNode* internal_node = (InternalNode*)edge.node_ref.node;
            usz edge_idx = edge.edge_idx;

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
            edge.node_ref.@output_dot_node(#output_item, out, $vasplat)!;

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
            usz edge_idx = edge.edge_idx;

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

fn Maybe{Type} BTree.first_item(&self)
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
    return maybe::value{Type}(node_ref.node.items[0]);
}

// TODO:
// macro void Map.@remove_if(&self, ???)
// It could be same as @get_existing_slots but @body can return whether to remove or not.
