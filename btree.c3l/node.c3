module btree(<Key, Val>);

const usz B = 6;
const usz CAPACITY = 2 * B - 1;
const usz MIN_LEN_AFTER_SPLIT = B - 1;
const usz KV_IDX_CENTER = B - 1;
const usz EDGE_IDX_LEFT_OF_CENTER = B - 1;
const usz EDGE_IDX_RIGHT_OF_CENTER = B;

struct LeafNode
{
    InternalNode* parent;

    // This node's index into the parent node's `edges` array.
    // `node.parent.edges[node.parent_edge_idx]` should be the same thing as `node`.
    // This is only guaranteed to be initialized when `parent` is non-null.
    ushort parent_edge_idx;

    // The number of keys and values this node stores.
    ushort len;

    // The arrays storing the actual data of the node. Only the first `len` elements of each
    // array are initialized and valid.
    Key[CAPACITY] keys;
    Val[CAPACITY] vals;
}

struct InternalNode
{
    // This is the first member of the struct `InternalNode`
    // so all pointers to an internal node are also a pointers to a leaf node.
    LeafNode data;

    // The pointers to the children of this node. `len + 1` of these are considered
    // initialized and valid.
    LeafNode*[CAPACITY + 1] edges;
}

struct NodeRef
{
    // The number of levels that the node and the level of leaves are apart, a
    // constant that the node itself does not store.
    // We only need to store the height of the root
    // node, and derive every other node's height from it.
    // Must be zero if type is leaf and non-zero if type is internal.
    usz height;
    // The pointer to the leaf or internal node. The definition of `InternalNode`
    // ensures that the pointer is valid either way.
    LeafNode* node;
}

// A reference to a specific key-value pair.
struct HandleKV
{
    NodeRef node_ref;
    usz kv_idx;
}

// A reference to a specific edge within a node.
//
// Note that even leaf nodes can have edge handles. Instead of representing a pointer to
// a child node, these represent the spaces where child pointers would go between the key-value
// pairs. For example, in a node with length 2, there would be 3 possible edge locations - one
// to the left of the node, one between the two pairs, and one at the right of the node.
struct HandleEdge
{
    NodeRef node_ref;  // Parent node. Child node may not exist if the parent is a leaf.
    usz edge_idx;
}

// ----------------------------------------------------------------------------
// INSERTION
// ----------------------------------------------------------------------------

struct SplitPoint
{
    usz middle_kv_idx;
    usz insert_idx;
    // Determines whether `insert_idx` is edge index in the left or in the right part.
    bool insert_into_left;
}

// Given an edge index where we want to insert into a node filled to capacity,
// computes a sensible KV index of a split point and where to perform the insertion.
// The goal of the split point is for its key and value to end up in a parent node;
// the keys, values and edges to the left of the split point become the left child;
// the keys, values and edges to the right of the split point become the right child.
<*
 @require edge_idx <= CAPACITY
*>
fn SplitPoint split_point(usz edge_idx)
{
    // Rust issue #74834 tries to explain these symmetric rules.
    switch
    {
        // Insert into the left node.
        case edge_idx < EDGE_IDX_LEFT_OF_CENTER:
            return { KV_IDX_CENTER - 1, edge_idx, true };
        case edge_idx == EDGE_IDX_LEFT_OF_CENTER:
            return { KV_IDX_CENTER, edge_idx, true };
        // Insert into the right node.
        case edge_idx == EDGE_IDX_RIGHT_OF_CENTER:
            return { KV_IDX_CENTER, 0, false };
        default:
            return { KV_IDX_CENTER + 1, edge_idx - (KV_IDX_CENTER + 1 + 1), false };
    }
}

// `keys` is the slice with existing keys.
<*
 @require at < CAPACITY
*>
fn void slice_insert_key(Key[] keys, usz at, Key key)
{
    if (keys.len != at)
    {
        // We need to move elements.
        mem::move(keys.ptr + at + 1, keys.ptr + at, (keys.len - at) * Key.sizeof);
    }
    keys.ptr[at] = key;
}

// `vals` is the slice with existing values.
<*
 @require at < CAPACITY
*>
fn void slice_insert_val(Val[] vals, usz at, Val val)
{
    if (vals.len != at)
    {
        // We need to move elements.
        mem::move(vals.ptr + at + 1, vals.ptr + at, (vals.len - at) * Val.sizeof);
    }
    vals.ptr[at] = val;
}

// `edges` is the slice with existing edges.
<*
 @require at < CAPACITY + 1
*>
fn void slice_insert_edge(LeafNode*[] edges, usz at, LeafNode* edge)
{
    if (edges.len != at)
    {
        // We need to move elements.
        mem::move(edges.ptr + at + 1, edges.ptr + at, (edges.len - at) * (LeafNode*).sizeof);
    }
    edges.ptr[at] = edge;
}

// Inserts a new key-value pair between the key-value pairs to the right and left of
// this edge. This method assumes that there is enough space in the node for the new
// pair to fit.
<*
 @require self.node_ref.node.len < CAPACITY
*>
fn HandleKV HandleEdge.insert_fit_into_leaf(self, Key key, Val val)
{
    LeafNode* node = self.node_ref.node;
    usz cur_len = node.len;
    slice_insert_key(node.keys[:cur_len], self.edge_idx, key);
    slice_insert_val(node.vals[:cur_len], self.edge_idx, val);
    node.len++;

    return HandleKV { .node_ref = self.node_ref, .kv_idx = self.edge_idx };
}

// Result of insertion, when a node needed to expand beyond its capacity.
//
// If `left.node` or `right.node` is null then there's no split result.
struct SplitResult
{
    // Altered node in existing tree with elements and edges that belong to the left of kv.
    NodeRef left;
    // Unattached, new node with elements and edges that belong to the right of kv.
    NodeRef right;

    // Some key and value that existed before and were split off, to be inserted elsewhere.
    Key key;
    Val val;
}

// Splits the underlying node into three parts:
//
// - The node is truncated to only contain the key-value pairs to the left of
//   this handle.
// - The key and value pointed to by this handle are extracted.
// - All the key-value pairs to the right of this handle are put into a newly
//   allocated node.
fn SplitResult HandleKV.split_leaf(self, Allocator allocator)
{
    LeafNode* orig_node = self.node_ref.node;  // Left node.

    SplitResult result;
    result.left = self.node_ref;
    result.key = orig_node.keys[self.kv_idx];
    result.val = orig_node.vals[self.kv_idx];

    LeafNode* new_node = allocator::alloc(allocator, LeafNode);  // Right node.
    new_node.len = orig_node.len - (ushort)self.kv_idx - 1;
    mem::copy(&new_node.keys, &orig_node.keys[self.kv_idx + 1], new_node.len * Key.sizeof);
    mem::copy(&new_node.vals, &orig_node.vals[self.kv_idx + 1], new_node.len * Val.sizeof);
    result.right.node = new_node;

    orig_node.len = (ushort)self.kv_idx;

    return result;
}

struct InsertIntoLeafResult
{
    SplitResult split;
    HandleKV handle;
}

// Inserts a new key-value pair between the key-value pairs to the right and left of
// this edge. This method splits the node if there isn't enough room.
fn InsertIntoLeafResult HandleEdge.insert_into_leaf(self, Key key, Val val, Allocator allocator)
{
    InsertIntoLeafResult insert_result;

    if (self.node_ref.node.len < CAPACITY)
    {
        insert_result.handle = self.insert_fit_into_leaf(key, val);
    }
    else
    {
        SplitPoint sp = split_point(self.edge_idx);
        HandleKV middle = { .node_ref = self.node_ref, .kv_idx = sp.middle_kv_idx };
        insert_result.split = middle.split_leaf(allocator);
        HandleEdge insertion_edge = {
            .node_ref = sp.insert_into_left ? insert_result.split.left : insert_result.split.right,
            .edge_idx = sp.insert_idx,
        };
        insert_result.handle = insertion_edge.insert_fit_into_leaf(key, val);
    }

    return insert_result;
}

// `from` and `to_excl` are for edge indices.
fn void InternalNode.correct_childrens_parent_links(&self, usz from, usz to_excl)
{
    for (usz i = from; i < to_excl; i++)
    {
        LeafNode* child = self.edges[i];
        child.parent = self;
        child.parent_edge_idx = (ushort)i;
    }
}

// TODO: Why has `edge` parameter in `insert_fit_into_internal` type `NodeRef`
//       instead of `LeafNode*`. We use it to check height but is that necessary?

// Inserts a new key-value pair and an edge that will go to the right of that new pair
// between this edge and the key-value pair to the right of this edge. This method assumes
// that there is enough space in the node for the new pair to fit.
<*
 @require self.node_ref.node.len < CAPACITY
 @require edge.height == self.node_ref.height - 1
*>
fn void HandleEdge.insert_fit_into_internal(self, Key key, Val val, NodeRef edge)
{
    LeafNode* node = self.node_ref.node;
    usz cur_len = node.len;
    slice_insert_key(node.keys[:cur_len], self.edge_idx, key);
    slice_insert_val(node.vals[:cur_len], self.edge_idx, val);
    InternalNode* internal_node = (InternalNode*)node;
    slice_insert_edge(internal_node.edges[:cur_len+1], self.edge_idx + 1, edge.node);
    node.len++;

    internal_node.correct_childrens_parent_links(self.edge_idx + 1, (usz)node.len + 1);
}

fn SplitResult HandleKV.split_internal(self, Allocator allocator)
{
    InternalNode* orig_node = (InternalNode*)self.node_ref.node;  // Left node.

    SplitResult result;
    result.left = self.node_ref;
    result.key = orig_node.data.keys[self.kv_idx];
    result.val = orig_node.data.vals[self.kv_idx];

    InternalNode* new_node = allocator::alloc(allocator, InternalNode);  // Right node.
    new_node.data.len = orig_node.data.len - (ushort)self.kv_idx - 1;
    mem::copy(&new_node.data.keys, &orig_node.data.keys[self.kv_idx + 1], new_node.data.len * Key.sizeof);
    mem::copy(&new_node.data.vals, &orig_node.data.vals[self.kv_idx + 1], new_node.data.len * Val.sizeof);
    mem::copy(&new_node.edges, &orig_node.edges[self.kv_idx + 1], ((usz)new_node.data.len + 1) * (LeafNode*).sizeof);
    result.right.node = &new_node.data;
    result.right.height = self.node_ref.height;

    orig_node.data.len = (ushort)self.kv_idx;  // CONSIDER: Shall we set moved keys and values to zero?

    return result;
}

// Inserts a new key-value pair and an edge that will go to the right of that new pair
// between this edge and the key-value pair to the right of this edge. This method splits
// the node if there isn't enough room.
<*
 @require edge.height == self.node_ref.height - 1
*>
fn SplitResult HandleEdge.insert_into_internal(self, Key key, Val val, NodeRef edge, Allocator allocator)
{
    SplitResult split_result;

    if (self.node_ref.node.len < CAPACITY)
    {
        self.insert_fit_into_internal(key, val, edge);
    }
    else
    {
        SplitPoint sp = split_point(self.edge_idx);
        HandleKV middle = { .node_ref = self.node_ref, .kv_idx = sp.middle_kv_idx };
        split_result = middle.split_internal(allocator);
        HandleEdge insertion_edge = {
            .node_ref = sp.insert_into_left ? split_result.left : split_result.right,
            .edge_idx = sp.insert_idx,
        };
        insertion_edge.insert_fit_into_internal(key, val, edge);
    }

    return split_result;
}

// Inserts a new key-value pair between the key-value pairs to the right and left of
// this edge. This method splits the node if there isn't enough room, and tries to
// insert the split off portion into the parent node recursively, until the root is reached.
//
// If the returned result is some `SplitResult`, the `left` field will be the root node.
// The returned pointer points to the inserted value, which in the case of `SplitResult`
// is in the `left` or `right` tree.
fn HandleKV HandleEdge.insert_into_leaf_recursing_up(self, Key key, Val val, NodeRef* orig_root, Allocator allocator)
{
    InsertIntoLeafResult insert_result = self.insert_into_leaf(key, val, allocator);

    // No split has been performed.
    if (insert_result.split.left.node == null) return insert_result.handle;

    SplitResult split = insert_result.split;

    while (true)
    {
        InternalNode* parent = split.left.node.parent;

        if (parent != null)
        {
            // Node which has been split has a parent.
            // Insert into the parent.
            HandleEdge parent_edge = {
                .node_ref = {
                    .height = split.left.height + 1,
                    .node = (LeafNode*)parent,
                },
                // `insert_into_internal` will insert a key and a value at `edge_idx`.
                // It will insert new edge at `edge_idx + 1`.
                // This means that edge at `edge_idx` and edges before it will be untouched.
                .edge_idx = split.left.node.parent_edge_idx
            };
            split = parent_edge.insert_into_internal(split.key, split.val, split.right, allocator);

            // If the parent hasn't been split then stop.
            // Otherwise continue.
            if (split.left.node == null) return insert_result.handle;
        }
        else
        {
            // Root has been split. Replace the original root by a newly constructed root.
            InternalNode* new_root = allocator::alloc(allocator, InternalNode);
            new_root.data.keys[0] = split.key;
            new_root.data.vals[0] = split.val;
            new_root.data.len = 1;
            new_root.edges[0] = split.left.node;
            new_root.edges[1] = split.right.node;

            new_root.correct_childrens_parent_links(0, 2);

            orig_root.node = &new_root.data;
            orig_root.height = split.left.height + 1;

            return insert_result.handle;
        }
    }
}
