module btree <Type>;

// Returns edge where `self` was. The returned edge is inside leaf.
// CAREFUL: `remove_leaf_item` returns different `HandleEdge` than `remove_internal_item`!
fn HandleEdge HandleItem.remove_leaf_item(self, NodeRef* orig_root, Allocator allocator)
{
    HandleEdge hole = {
        .node_ref = self.node_ref,
        .edge_idx = self.item_idx,
    };
    {
        LeafNode* node = self.node_ref.node;
        mem_move_items(node, self.item_idx, self.item_idx + 1, node.len - self.item_idx - 1);
        node.len--;

        // No need to rebalance.
        // It's okay if `node` is empty root which is leaf.
        if (node.len >= MIN_LEN_AFTER_SPLIT || !node.parent) return hole;
    }

    // Rebalance leaf.
    // The algorithm is same as for internal nodes,
    // the only difference is that it updates resulting position of `hole`.
    // Note that the position of `hole` won't change by balancing internal nodes later in the code.
    NodeRef node_ref = self.node_ref;
    {
        BalancingContext ctx = node_ref.choose_parent_item();

        if (ctx.can_merge())
        {
            // Our underfull leaf is right child.
            if (!ctx.balancing_left_child)
            {
                // Right child will be freed by `do_merge` so our `hole`
                // moves into left child.
                hole = {
                    .node_ref = ctx.left_child,
                    // We need original `ctx.left_child.node.len` before `do_merge`!
                    .edge_idx = (sz)ctx.left_child.node.len + 1 + hole.edge_idx,
                };
            }
            ctx.do_merge(allocator);

            // At this point parent node could be underfull so we have to continue.
            node_ref = ctx.parent.node_ref;
        }
        else
        {
            if (ctx.balancing_left_child)
            {
                ctx.bulk_steal_right(1);
            }
            else
            {
                hole.edge_idx++;
                ctx.bulk_steal_left(1);
            }

            // At this point no node is underfull so we can stop balancing.
            return hole;
        }
    }

    // Rebalance internal nodes.
    while (true)
    {
        // Node is not underfull so there is no need to rebalance.
        if (node_ref.node.len >= MIN_LEN_AFTER_SPLIT) return hole;

        // Node is internal root.
        // Such root must contain at least one item.
        if (!node_ref.node.parent)
        {
            // Underfull root is fine unless it's empty.
            if (node_ref.node.len != 0) return hole;

            LeafNode* new_root = ((InternalNode*)node_ref.node).edges[0];
            new_root.parent = null;
            // `new_root.parent_edge_idx` is already 0.

            // Replace root by its left child.
            *orig_root = {
                .height = node_ref.height - 1,
                .node = new_root,
            };
            alloc::free(allocator, node_ref.node);

            return hole;
        }

        BalancingContext ctx = node_ref.choose_parent_item();

        if (ctx.can_merge())
        {
            ctx.do_merge(allocator);

            // At this point parent node could be underfull so we have to continue.
            node_ref = ctx.parent.node_ref;
        }
        else
        {
            if (ctx.balancing_left_child)
            {
                ctx.bulk_steal_right(1);
            }
            else
            {
                ctx.bulk_steal_left(1);
            }

            // At this point no node is underfull so we can stop balancing.
            return hole;
        }
    }
}

// Returns edge before predecessor of `self`. The returned edge is inside leaf.
// CAREFUL: `remove_internal_item` returns different `HandleEdge` than `remove_leaf_item`!
fn HandleEdge HandleItem.remove_internal_item(self, NodeRef* orig_root, Allocator allocator)
{
    // In the left subtree find the rightmost leaf.
    NodeRef node_ref = {
        .height = self.node_ref.height - 1,
        .node = ((InternalNode*)self.node_ref.node).edges[self.item_idx]
    };
    while (node_ref.height > 0)  // Go to the leaf.
    {
        node_ref = {
            .height = node_ref.height - 1,
            .node = ((InternalNode*)node_ref.node).edges[node_ref.node.len],
        };
    }

    // Replace the original item with the rightmost item from the leaf
    // and remove the rightmost item from the leaf.
    sz item_to_remove_idx = (sz)node_ref.node.len - 1;
    self.node_ref.node.items[self.item_idx] = node_ref.node.items[item_to_remove_idx];
    HandleItem to_remove = {
        .node_ref = node_ref,
        .item_idx = item_to_remove_idx,
    };
    return to_remove.remove_leaf_item(orig_root, allocator);
}

fn void HandleItem.remove_item(self, NodeRef* orig_root, Allocator allocator)
{
    if (self.node_ref.height == 0)
    {
        self.remove_leaf_item(orig_root, allocator);
    }
    else
    {
        self.remove_internal_item(orig_root, allocator);
    }
}
