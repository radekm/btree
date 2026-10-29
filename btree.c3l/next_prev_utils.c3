module btree <Type>;

<*
 @require edge.node_ref.height == 0
*>
fn bool handle_edge_in_leaf_next_item(HandleEdge edge, HandleItem* out_item) @private
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
		// There's an item on the right of `edge`.
		*out_item = { .node_ref = edge.node_ref, .item_idx = edge.edge_idx };
		return true;
	}

	// No next item (it is the last edge).
	return false;

}

<*
 @require edge.node_ref.height == 0
*>
fn bool handle_edge_in_leaf_prev_item(HandleEdge edge, HandleItem* out_item) @private
{
	// While it's not possible to go left, go up.
	while (edge.edge_idx == 0 && edge.node_ref.node.parent)
	{
		edge = {
			.node_ref = {
				.height = edge.node_ref.height + 1,
				.node = &edge.node_ref.node.parent.data,
			},
			.edge_idx = edge.node_ref.node.parent_edge_idx,
		};
	}

	if (edge.edge_idx > 0)
	{
		// It's possible to go left.
		// There's an item on the left of `edge`.
		*out_item = { .node_ref = edge.node_ref, .item_idx = edge.edge_idx - 1 };
		return true;
	}

	// No prev item (it is the first edge).
	return false;
}

fn bool handle_edge_next_item(HandleEdge edge, HandleItem* out_item) @private
{
	// Go to the leaf.
	while (edge.node_ref.height > 0)
	{
		InternalNode* internal_node = (InternalNode*)edge.node_ref.node;
		// Leftmost edge.
		edge = {
			.node_ref = {
				.height = edge.node_ref.height - 1,
				.node = internal_node.edges[edge.edge_idx],
			},
		};
	}

	return handle_edge_in_leaf_next_item(edge, out_item);
}

fn bool handle_edge_prev_item(HandleEdge edge, HandleItem* out_item) @private
{
	// Go to the leaf.
	while (edge.node_ref.height > 0)
	{
		InternalNode* internal_node = (InternalNode*)edge.node_ref.node;
		LeafNode* child = internal_node.edges[edge.edge_idx];
		// Rightmost edge.
		edge = {
			.node_ref = {
				.height = edge.node_ref.height - 1,
				.node = child,
			},
			.edge_idx = child.len,
		};
	}

	return handle_edge_in_leaf_prev_item(edge, out_item);
}

fn bool handle_item_next_item(HandleItem item, HandleItem* out_item) @private
{
	// Edge on the right of `item`.
	HandleEdge edge = { .node_ref = item.node_ref, .edge_idx = item.item_idx + 1 };
	return handle_edge_next_item(edge, out_item);
}

fn bool handle_item_prev_item(HandleItem item, HandleItem* out_item) @private
{
	// Edge on the left of `item`.
	HandleEdge edge = { .node_ref = item.node_ref, .edge_idx = item.item_idx };
	return handle_edge_prev_item(edge, out_item);
}
