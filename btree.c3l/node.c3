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
 @require dest_idx <= CAPACITY && dest_idx + count <= CAPACITY
 @require src_idx <= CAPACITY && src_idx + count <= CAPACITY
*>
fn void mem_copy_items(LeafNode* dest, usz dest_idx, LeafNode* src, usz src_idx, usz count)
{
    // We do pointer arithmetic because `&dest.items[dest_idx]`
    // may fail with index out of bounds when `dest_idx == dest.len` and `count == 0`.
   mem::copy(
        &dest.items[0] + dest_idx,
        &src.items[0] + src_idx,
        count * Type.sizeof);
}

<*
 @require dest_idx <= CAPACITY && dest_idx + count <= CAPACITY
 @require src_idx <= CAPACITY && src_idx + count <= CAPACITY
*>
fn void mem_move_items(LeafNode* dest_and_src, usz dest_idx, usz src_idx, usz count)
{
    mem::move(
        &dest_and_src.items[0] + dest_idx,
        &dest_and_src.items[0] + src_idx,
        count * Type.sizeof);
}

<*
 @require dest != src : "Aliasing is not allowed"
 @require dest_idx <= CAPACITY + 1 && dest_idx + count <= CAPACITY + 1
 @require src_idx <= CAPACITY + 1 && src_idx + count <= CAPACITY + 1
*>
fn void mem_copy_edges(InternalNode* dest, usz dest_idx, InternalNode* src, usz src_idx, usz count)
{
    mem::copy(
        &dest.edges[0] + dest_idx,
        &src.edges[0] + src_idx,
        count * (LeafNode*).sizeof);
}

<*
 @require dest_idx <= CAPACITY + 1 && dest_idx + count <= CAPACITY + 1
 @require src_idx <= CAPACITY + 1 && src_idx + count <= CAPACITY + 1
*>
fn void mem_move_edges(InternalNode* dest_and_src, usz dest_idx, usz src_idx, usz count)
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
    new_node.len = (ushort)((usz)orig_node.len - self.item_idx - 1);
    mem_copy_items(new_node, 0, orig_node, self.item_idx + 1, new_node.len);
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

    internal_node.correct_childrens_parent_links(self.edge_idx + 1, (usz)node.len + 1);
}

fn SplitResult HandleItem.split_internal(self, Allocator allocator)
{
    InternalNode* orig_node = (InternalNode*)self.node_ref.node;  // Left node.

    SplitResult result;
    result.left = self.node_ref;
    result.item = orig_node.data.items[self.item_idx];

    InternalNode* new_node = allocator::new(allocator, InternalNode);  // Right node.
    new_node.data.len = (ushort)((usz)orig_node.data.len - self.item_idx - 1);
    mem_copy_items(&new_node.data, 0, &orig_node.data, self.item_idx + 1, new_node.data.len);
    mem_copy_edges(new_node, 0, orig_node, self.item_idx + 1, (usz)new_node.data.len + 1);
    new_node.correct_childrens_parent_links(0, (usz)new_node.data.len + 1);
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

// ----------------------------------------------------------------------------
// BALANCING UNDERFULL NODES AFTER REMOVAL
// ----------------------------------------------------------------------------

// Represents a session for evaluating and performing a balancing operation
// around an internal item.
struct BalancingContext
{
    HandleItem parent;
    NodeRef left_child;
    NodeRef right_child;

    // Determines whether we're balancing parent's left or right child.
    // We prefer balancing contexts where we're balancing right child
    // (ie. where right child is underfull).
    //
    // The reason why we prefer right child to be underfull is speed.
    // (1) When merging our implementation always merges right child
    //     into left child. So if right child is underfull then
    //     we have to copy less items and less edges.
    // (2) When stealing from left child we have to shift
    //     items and edges in underfull right child.
    //     When stealing from right child we have to shift
    //     items and edges in right child which is not underfull.
    //     So in the first case we have to shift less items and edges
    //     because the node is underfull.
    bool balancing_left_child;
}

// Chooses a balancing context involving the node as a child, thus between
// the item immediately to the left or to the right in the parent node.
// Fails if `self` has no parent or if the parent is empty.
//
// Prefers placing `self` as right child in the returned balancing context.
<*
 @require self.node.parent != null
 @require self.node.parent.data.len > 0
*>
fn BalancingContext NodeRef.choose_parent_item(self)
{
    InternalNode* parent = self.node.parent;

    // The condition `self.node.parent_edge_idx != 0` is true iff `self` is not the leftmost child.
    // And so if the condition is true we can create a balancing context where `self` is the right child.
    if (self.node.parent_edge_idx != 0)
    {
        return {
            .parent = {
                .node_ref = {
                    .height = self.height + 1,
                    .node = &parent.data,
                },
                .item_idx = (usz)self.node.parent_edge_idx - 1,
            },
            .left_child = {
                .height = self.height,
                .node = parent.edges[self.node.parent_edge_idx - 1],
            },
            .right_child = self,
            .balancing_left_child = false,
        };
    }
    else
    {
        return {
            .parent = {
                .node_ref = {
                    .height = self.height + 1,
                    .node = &parent.data,
                },
                .item_idx = self.node.parent_edge_idx,
            },
            .left_child = self,
            .right_child = {
                .height = self.height,
                .node = parent.edges[self.node.parent_edge_idx + 1],
            },
            .balancing_left_child = true,
        };
    }
}

fn bool BalancingContext.can_merge(self)
{
    return self.left_child.node.len + 1 + self.right_child.node.len <= CAPACITY;
}

// Merges the parent's item and both adjacent child nodes into
// the left child node and frees the right child node.
<*
 @require self.left_child.node.len + 1 + self.right_child.node.len <= CAPACITY : "Cannot merge because node capacity would be exceeded"
*>
fn void BalancingContext.do_merge(self, Allocator allocator)
{
    InternalNode* parent = (InternalNode*)self.parent.node_ref.node;
    LeafNode* left_child = self.left_child.node;
    LeafNode* right_child = self.right_child.node;

    // Move items to left child.

    left_child.items[left_child.len] = parent.data.items[self.parent.item_idx];
    mem_copy_items(
        left_child, (usz)left_child.len + 1,
        right_child, 0,
        right_child.len);

    // Remove item from parent.
    usz num_of_items_to_move = parent.data.len - self.parent.item_idx - 1;
    mem_move_items(
        &parent.data,
        // `self.parent.item_idx` is left edge before the item which has been moved from parent.
        // This edge should be preserved but the item immediatelly after it was moved.
        self.parent.item_idx,
        self.parent.item_idx + 1,
        num_of_items_to_move);

    // Remove edge leading to right child from parent

    // `parent.data.len + 1` is the original number of edges before removal.
    usz num_of_remaining_edges = parent.data.len;
    // The number edges which don't need to move (left edge and all edges on its left side).
    usz num_of_edges_to_stay = self.parent.item_idx + 1;
    usz num_of_edges_to_move = num_of_remaining_edges - num_of_edges_to_stay;
    mem_move_edges(
        parent,
        // `self.parent.item_idx` is left edge before the item which has been moved from parent.
        // This edge should be preserved.
        // `self.parent.item_idx + 1` is right edge which should be removed.
        self.parent.item_idx + 1,
        self.parent.item_idx + 2,
        num_of_edges_to_move);
    parent.correct_childrens_parent_links(num_of_edges_to_stay, num_of_remaining_edges);

    // If children are not leaves then copy edges from right child to left child.
    if (self.left_child.height > 0)
    {
        InternalNode* left = (InternalNode*)left_child;
        InternalNode* right = (InternalNode*)right_child;
        mem_copy_edges(
            left, (usz)left_child.len + 1,
            right, 0,
            (usz)right_child.len + 1);
        left.correct_childrens_parent_links(
            (usz)left_child.len + 1,
            (usz)left_child.len + 1 + (usz)right_child.len + 1);
    }

    // Fix lengths.
    parent.data.len--;
    left_child.len += 1 + right_child.len;

    // Deallocate right node.
    allocator::free(allocator, right_child);
}

<*
 @require count > 0 : "Stealing no items doesn't make sense"
 @require self.left_child.node.len >= count : "Not enough items to steal"
 @require self.right_child.node.len + count <= CAPACITY : "Cannot steal because node capacity would be exceeded"
*>
fn void BalancingContext.bulk_steal_left(self, usz count)
{
    LeafNode* parent = self.parent.node_ref.node;
    LeafNode* left_child = self.left_child.node;
    LeafNode* right_child = self.right_child.node;

    // Make room for stolen items.
    mem_move_items(right_child, count, 0, right_child.len);
    // Move item from parent to right child.
    right_child.items[count - 1] = parent.items[self.parent.item_idx];
    // Move items from left child to right child.
    mem_copy_items(right_child, 0, left_child, left_child.len - (count - 1), count - 1);
    // Move item from left child to parent.
    parent.items[self.parent.item_idx] = left_child.items[left_child.len - count];

    // If children are not leaves then move edges from left child to right child.
    if (self.left_child.height > 0)
    {
        InternalNode* left = (InternalNode*)left_child;
        InternalNode* right = (InternalNode*)right_child;

        // Make room for stolen edges.
        mem_move_edges(right, count, 0, (usz)right_child.len + 1);
        // Move edges.
        mem_copy_edges(right, 0, left, (usz)left_child.len + 1 - count, count);

        // We have to correct parent links from all children
        // (existing children were shifted so their `parent_edge_idx` changed).
        right.correct_childrens_parent_links(0, (usz)right_child.len + 1 + count);
    }

    left_child.len -= (ushort)count;
    right_child.len += (ushort)count;
}

<*
 @require count > 0 : "Stealing no items doesn't make sense"
 @require self.left_child.node.len + count <= CAPACITY : "Cannot steal because node capacity would be exceeded"
 @require self.right_child.node.len >= count : "Not enough items to steal"
*>
fn void BalancingContext.bulk_steal_right(self, usz count)
{
    LeafNode* parent = self.parent.node_ref.node;
    LeafNode* left_child = self.left_child.node;
    LeafNode* right_child = self.right_child.node;

    // Move item from parent to left child.
    left_child.items[left_child.len] = parent.items[self.parent.item_idx];
    // Move items from right child to left child.
    mem_copy_items(left_child, (usz)left_child.len + 1, right_child, 0, count - 1);
    // Move item from right child to parent.
    parent.items[self.parent.item_idx] = right_child.items[count - 1];
    // Shift remaining items in right child.
    mem_move_items(right_child, 0, count, right_child.len - count);

    // If children are not leaves then move edges from right child to left child.
    if (self.left_child.height > 0)
    {
        InternalNode* left = (InternalNode*)left_child;
        InternalNode* right = (InternalNode*)right_child;

        // Move edges.
        mem_copy_edges(left, (usz)left_child.len + 1, right, 0, count);
        // Shift remaining edges in right child.
        mem_move_edges(right, 0, count, (usz)right_child.len + 1 - count);

        // We have to correct parent links.
        left.correct_childrens_parent_links((usz)left_child.len + 1, (usz)left_child.len + 1 + count);
        right.correct_childrens_parent_links(0, (usz)right_child.len + 1 - count);
    }

    left_child.len += (ushort)count;
    right_child.len -= (ushort)count;
}
