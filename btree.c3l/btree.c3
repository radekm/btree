module btree{Type};

struct SearchResult
{
    bool found;
    union
    {
        HandleItem existing_item;
        HandleEdge insert_position;
    }
}

// Trailing body is a comparison code.
// It shall return `x < 0` if we search for something smaller than `item_from_tree` given to it.
// It shall return `x > 0` if we search for something bigger than `item_from_tree` given to it.
// Otherwise `item` given to it is what we search for `@body` should return `x == 0`.
//
// NOTE: It seems that `@body` can't return a value to circumvent this we added
//       `x` to which `@body` assigns the result.
macro SearchResult NodeRef.@search_tree(self; @body(Type item_from_tree, int* x))
{
    NodeRef root = self;

    while (true)
    {
        LeafNode* node = root.node;

        int edge;
        for (; edge < node.len; edge++)
        {
            int x;
            @body(node.items[edge], &x);
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
        .root = { .node = allocator::alloc(allocator, LeafNode) },
        .allocator = allocator
    };
}

struct BTreeSlot
{
    bool existed;
    Type* item;
}

// CONSIDER: Return `Type*?` instead?
macro BTreeSlot BTree.@get_existing_slot(&self; @body(Type item_from_tree, int* x))
{
    SearchResult sr = self.root.@search_tree(; Type item_from_tree, int* x)
    {
        @body(item_from_tree, x);
    };

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

macro BTreeSlot BTree.@get_slot(&self; @body(Type item_from_tree, int* x))
{
    SearchResult sr = self.root.@search_tree(; Type item_from_tree, int* x)
    {
        @body(item_from_tree, x);
    };

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

// TODO:
// macro void Map.@remove_if(&self, ???)
// It could be same as @get_existing_slots but @body can return whether to remove or not.

// TODO:
// Add a function to free BTree.
