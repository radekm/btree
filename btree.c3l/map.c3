module btree(<Key, Val>);

import std::core::builtin;

def CmpFn = fn int(Key, Key, void*);

// CONSIDER: Rename this to avoid conflict with std lib.
struct SearchResult
{
    bool found;
    union
    {
        HandleKV existing_kv;
        HandleEdge insert_position;
    }
}

fn SearchResult search_tree(NodeRef root, Key key, CmpFn cmp, void* ctx)
{
    while (true)
    {
        LeafNode* node = root.node;

        int edge;
        for (; edge < node.len; edge++)
        {
            int x = cmp(key, node.keys[edge], ctx);
            if (x < 0)
            {
                // `key` is smaller than `node.keys[edge]`.
                // We have to go down if possible.
                break;
            }
            else if (x > 0)
            {
                // `key` is bigger than `node.keys[edge]`.
                // Go to the right. At this point it is possible.
            }
            else
            {
                // We found `key`.
                SearchResult result;
                result.found = true;
                result.existing_kv = {
                    .node_ref = root,
                    .kv_idx = edge,
                };
                return result;
            }
        }

        // `key` wasn't found in current `root`.
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

// We don't allow zeroed map because `cmp` is necessary.
// CONSIDER: Store the number of elements.
struct Map
{
    NodeRef root;
    CmpFn cmp;
    void* ctx;
    Allocator allocator;
}

fn void Map.init(&self, CmpFn cmp, void* ctx = null, Allocator allocator = allocator::heap())
{
    *self = {
        .root = { .node = allocator::alloc(allocator, LeafNode) },
        .cmp = cmp,
        .ctx = ctx,
        .allocator = allocator
    };
}

macro void Map.@get_existing_slots(&self, Key key; @body(bool existed, Key* key_slot, Val* val_slot))
{
    SearchResult sr = search_tree(self.root, key, self.cmp, self.ctx);
    if (!sr.found)
    {
        @body(false, null, null);
    }
    else
    {
        LeafNode* node = sr.existing_kv.node_ref.node;
        @body(true, &node.keys[sr.existing_kv.kv_idx], &node.vals[sr.existing_kv.kv_idx]);
    }
}

macro void Map.@get_slots(&self, Key key; @body(bool existed, Key* key_slot, Val* val_slot))
{
    SearchResult sr = search_tree(self.root, key, self.cmp, self.ctx);
    HandleKV handle;
    if (sr.found)
    {
        handle = sr.existing_kv;
    }
    else
    {
        handle = sr.insert_position.insert_into_leaf_recursing_up({}, {}, &self.root, self.allocator);
    }

    LeafNode* node = handle.node_ref.node;
    @body(sr.found, &node.keys[handle.kv_idx], &node.vals[handle.kv_idx]);
}

// TODO:
// macro void Map.@remove_if(&self, ???)
// It could be same as @get_existing_slots but @body can return whether to remove or not.

fn Val*! Map.get_ref(&self, Key key)
{
    self.@get_existing_slots(key; bool existed, Key* k, Val* v)
    {
        if (!existed) return std::core::builtin::SearchResult.MISSING?;
        return v;
    };
}

fn Val! Map.get(&self, Key key) @operator([])
{
    return *self.get_ref(key);
}

fn bool Map.has_key(self, Key key)
{
    return @ok(self.get_ref(key));
}

macro Val Map.set_value_return(&self, Key key, Val val) @operator([]=)
{
    self.set(key, val);
    return val;
}

fn bool Map.set(&self, Key key, Val val)
{
    self.@get_slots(key; bool existed, Key* k, Val* v)
    {
        *k = key;
        *v = val;
        return existed;
    };
}
