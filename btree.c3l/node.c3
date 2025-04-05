module btree{Type};

const usz B = 6;
const usz CAPACITY = 2 * B - 1;
const usz MIN_LEN_AFTER_SPLIT = B - 1;
const usz ITEM_IDX_CENTER = B - 1;
const usz EDGE_IDX_LEFT_OF_CENTER = B - 1;
const usz EDGE_IDX_RIGHT_OF_CENTER = B;

struct LeafNode
{
    InternalNode* parent;

    // This node's index into the parent node's `edges` array.
    // `node.parent.edges[node.parent_edge_idx]` should be the same thing as `node`.
    // This is only guaranteed to be initialized when `parent` is non-null.
    ushort parent_edge_idx;

    // The number items this node stores.
    ushort len;

    // The array storing the actual data of the node. Only the first `len` elements
    // are initialized and valid.
    Type[CAPACITY] items;
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

// A reference to a specific item.
struct HandleItem
{
    NodeRef node_ref;
    usz item_idx;
}

// A reference to a specific edge within a node.
//
// Note that even leaf nodes can have edge handles. Instead of representing a pointer to
// a child node, these represent the spaces where child pointers would go between the items.
// For example, in a node with length 2, there would be 3 possible edge locations - one
// to the left of the node, one between the two items, and one at the right of the node.
struct HandleEdge
{
    NodeRef node_ref;  // Parent node. Child node may not exist if the parent is a leaf.
    usz edge_idx;
}

// ----------------------------------------------------------------------------
// HELPERS
// ----------------------------------------------------------------------------

<*
 @require dest != src : "Aliasing is not allowed"
 @require dest_idx <= CAPACITY && dest_idx + count <= (ushort)CAPACITY
 @require src_idx <= CAPACITY && src_idx + count <= (ushort)CAPACITY
*>
fn void mem_copy_items(LeafNode* dest, ushort dest_idx, LeafNode* src, ushort src_idx, ushort count)
{
    // We do pointer arithmetic because `&dest.items[dest_idx]`
    // may fail with index out of bounds when `dest_idx == dest.len` and `count == 0`.
   mem::copy(
        &dest.items[0] + dest_idx,
        &src.items[0] + src_idx,
        count * Type.sizeof);
}

<*
 @require dest_idx <= CAPACITY && dest_idx + count <= (ushort)CAPACITY
 @require src_idx <= CAPACITY && src_idx + count <= (ushort)CAPACITY
*>
fn void mem_move_items(LeafNode* dest_and_src, ushort dest_idx, ushort src_idx, ushort count)
{
    mem::move(
        &dest_and_src.items[0] + dest_idx,
        &dest_and_src.items[0] + src_idx,
        count * Type.sizeof);
}

<*
 @require dest != src : "Aliasing is not allowed"
 @require dest_idx <= (ushort)(CAPACITY + 1) && dest_idx + count <= (ushort)(CAPACITY + 1)
 @require src_idx <= (ushort)(CAPACITY + 1) && src_idx + count <= (ushort)(CAPACITY + 1)
*>
fn void mem_copy_edges(InternalNode* dest, ushort dest_idx, InternalNode* src, ushort src_idx, usz count)
{
    mem::copy(
        &dest.edges[0] + dest_idx,
        &src.edges[0] + src_idx,
        count * (LeafNode*).sizeof);
}

<*
 @require dest_idx <= (ushort)(CAPACITY + 1) && dest_idx + count <= (ushort)(CAPACITY + 1)
 @require src_idx <= (ushort)(CAPACITY + 1) && src_idx + count <= (ushort)(CAPACITY + 1)
*>
fn void mem_move_edges(InternalNode* dest_and_src, ushort dest_idx, ushort src_idx, ushort count)
{
    mem::move(
        &dest_and_src.edges[0] + dest_idx,
        &dest_and_src.edges[0] + src_idx,
        count * (LeafNode*).sizeof);
}

// ----------------------------------------------------------------------------
// INSERTION
// ----------------------------------------------------------------------------

struct SplitPoint
{
    usz middle_item_idx;
    usz insert_idx;
    // Determines whether `insert_idx` is edge index in the left or in the right part.
    bool insert_into_left;
}

// Given an edge index where we want to insert into a node filled to capacity,
// computes a sensible item index of a split point and where to perform the insertion.
// The goal of the split point is for its item to end up in a parent node;
// the items and edges to the left of the split point become the left child;
// the items and edges to the right of the split point become the right child.
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
            return { ITEM_IDX_CENTER - 1, edge_idx, true };
        case edge_idx == EDGE_IDX_LEFT_OF_CENTER:
            return { ITEM_IDX_CENTER, edge_idx, true };
        // Insert into the right node.
        case edge_idx == EDGE_IDX_RIGHT_OF_CENTER:
            return { ITEM_IDX_CENTER, 0, false };
        default:
            return { ITEM_IDX_CENTER + 1, edge_idx - (ITEM_IDX_CENTER + 1 + 1), false };
    }
}

// `items` is the slice with existing items.
<*
 @require at < CAPACITY
*>
fn void slice_insert_item(Type[] items, usz at, Type item)
{
    if (items.len != at)
    {
        // We need to move elements.
        mem::move(items.ptr + at + 1, items.ptr + at, (items.len - at) * Type.sizeof);
    }
    items.ptr[at] = item;
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

// Inserts a new item between the items to the right and left of
// this edge. This function assumes that there is enough space in the node for the item to fit.
<*
 @require self.node_ref.node.len < CAPACITY
*>
fn HandleItem HandleEdge.insert_fit_into_leaf(self, Type item)
{
    LeafNode* node = self.node_ref.node;
    usz cur_len = node.len;
    slice_insert_item(node.items[:cur_len], self.edge_idx, item);
    node.len++;

    return { .node_ref = self.node_ref, .item_idx = self.edge_idx };
}

// Result of insertion, when a node needed to expand beyond its capacity.
//
// If `left.node` or `right.node` is null then there's no split result.
struct SplitResult
{
    // Altered node in existing tree with elements and edges that belong to the left of item.
    NodeRef left;
    // Unattached, new node with elements and edges that belong to the right of item.
    NodeRef right;

    // Some item that existed before and were split off, to be inserted elsewhere.
    Type item;
}

// Splits the underlying node into three parts:
//
// - The node is truncated to only contain the items to the left of
//   this handle.
// - The item pointed to by this handle is extracted.
// - All the items to the right of this handle are put into a newly
//   allocated node.
fn SplitResult HandleItem.split_leaf(self, Allocator allocator)
{
    LeafNode* orig_node = self.node_ref.node;  // Left node.

    SplitResult result;
    result.left = self.node_ref;
    result.item = orig_node.items[self.item_idx];

    LeafNode* new_node = allocator::new(allocator, LeafNode);  // Right node.
    new_node.len = orig_node.len - (ushort)self.item_idx - 1;
    mem_copy_items(new_node, 0, orig_node, (ushort)self.item_idx + 1, new_node.len);
    result.right.node = new_node;

    orig_node.len = (ushort)self.item_idx;

    return result;
}

struct InsertIntoLeafResult
{
    SplitResult split;
    HandleItem handle;
}

// Inserts a new item between the items to the right and left of
// this edge. This method splits the node if there isn't enough room.
fn InsertIntoLeafResult HandleEdge.insert_into_leaf(self, Type item, Allocator allocator)
{
    InsertIntoLeafResult insert_result;

    if (self.node_ref.node.len < CAPACITY)
    {
        insert_result.handle = self.insert_fit_into_leaf(item);
    }
    else
    {
        SplitPoint sp = split_point(self.edge_idx);
        HandleItem middle = { .node_ref = self.node_ref, .item_idx = sp.middle_item_idx };
        insert_result.split = middle.split_leaf(allocator);
        HandleEdge insertion_edge = {
            .node_ref = sp.insert_into_left ? insert_result.split.left : insert_result.split.right,
            .edge_idx = sp.insert_idx,
        };
        insert_result.handle = insertion_edge.insert_fit_into_leaf(item);
    }

    return insert_result;
}

// `from` and `to_excl` are for edge indices.
<*
 @require from <= to_excl
 @require to_excl <= CAPACITY + 1
*>
fn void InternalNode.correct_childrens_parent_links(&self, ushort from, ushort to_excl)
{
    for (ushort i = from; i < to_excl; i++)
    {
        LeafNode* child = self.edges[i];
        child.parent = self;
        child.parent_edge_idx = i;
    }
}

// TODO: Why has `edge` parameter in `insert_fit_into_internal` type `NodeRef`
//       instead of `LeafNode*`. We use it to check height but is that necessary?

// Inserts a new item and an edge that will go to the right of that new item
// between this edge and the item to the right of this edge. This method assumes
// that there is enough space in the node for the new item to fit.
<*
 @require self.node_ref.node.len < CAPACITY
 @require edge.height == self.node_ref.height - 1
*>
fn void HandleEdge.insert_fit_into_internal(self, Type item, NodeRef edge)
{
    LeafNode* node = self.node_ref.node;
    usz cur_len = node.len;
    slice_insert_item(node.items[:cur_len], self.edge_idx, item);
    InternalNode* internal_node = (InternalNode*)node;
    slice_insert_edge(internal_node.edges[:cur_len+1], self.edge_idx + 1, edge.node);
    node.len++;

    internal_node.correct_childrens_parent_links((ushort)self.edge_idx + 1, node.len + 1);
}

fn SplitResult HandleItem.split_internal(self, Allocator allocator)
{
    InternalNode* orig_node = (InternalNode*)self.node_ref.node;  // Left node.

    SplitResult result;
    result.left = self.node_ref;
    result.item = orig_node.data.items[self.item_idx];

    InternalNode* new_node = allocator::new(allocator, InternalNode);  // Right node.
    new_node.data.len = orig_node.data.len - (ushort)self.item_idx - 1;
    mem_copy_items(&new_node.data, 0, &orig_node.data, (ushort)self.item_idx + 1, new_node.data.len);
    mem_copy_edges(new_node, 0, orig_node, (ushort)self.item_idx + 1, (usz)new_node.data.len + 1);
    new_node.correct_childrens_parent_links(0, new_node.data.len + 1);
    result.right.node = &new_node.data;
    result.right.height = self.node_ref.height;

    orig_node.data.len = (ushort)self.item_idx;  // CONSIDER: Shall we set moved out items to zero?

    return result;
}

// Inserts a new item and an edge that will go to the right of that new item
// between this edge and the item to the right of this edge. This method splits
// the node if there isn't enough room.
<*
 @require edge.height == self.node_ref.height - 1
*>
fn SplitResult HandleEdge.insert_into_internal(self, Type item, NodeRef edge, Allocator allocator)
{
    SplitResult split_result;

    if (self.node_ref.node.len < CAPACITY)
    {
        self.insert_fit_into_internal(item, edge);
    }
    else
    {
        SplitPoint sp = split_point(self.edge_idx);
        HandleItem middle = { .node_ref = self.node_ref, .item_idx = sp.middle_item_idx };
        split_result = middle.split_internal(allocator);
        HandleEdge insertion_edge = {
            .node_ref = sp.insert_into_left ? split_result.left : split_result.right,
            .edge_idx = sp.insert_idx,
        };
        insertion_edge.insert_fit_into_internal(item, edge);
    }

    return split_result;
}

// Inserts a new item between the items to the right and left of
// this edge. This method splits the node if there isn't enough room, and tries to
// insert the split off portion into the parent node recursively, until the root is reached.
//
// Returns handle pointing to the newly inserted item.
fn HandleItem HandleEdge.insert_into_leaf_recursing_up(self, Type item, NodeRef* orig_root, Allocator allocator)
{
    InsertIntoLeafResult insert_result = self.insert_into_leaf(item, allocator);

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
                // `insert_into_internal` will insert an item at `edge_idx`.
                // It will insert new edge at `edge_idx + 1`.
                // This means that edge at `edge_idx` and edges before it will be untouched.
                .edge_idx = split.left.node.parent_edge_idx
            };
            split = parent_edge.insert_into_internal(split.item, split.right, allocator);

            // If the parent hasn't been split then stop.
            // Otherwise continue.
            if (split.left.node == null) return insert_result.handle;
        }
        else
        {
            // Root has been split. Replace the original root by a newly constructed root.
            InternalNode* new_root = allocator::new(allocator, InternalNode);
            new_root.data.items[0] = split.item;
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
