module pool{Type};

import std;

typedef Handle = int;

union ItemOrFreelistNode
{
    Type item;
    Maybe{Handle} freelist_node;
}

struct Pool
{
    // `List` is not very efficient but we use it for simplicity.
    List{ItemOrFreelistNode} data;
    Maybe{Handle} first_freelist_node;
}

fn void Pool.init(&self, Allocator allocator)
{
    self.data.init(allocator);
    self.first_freelist_node = {};
}

fn void Pool.free(&self)
{
    self.data.free();
    self.first_freelist_node = {};
}

fn Handle Pool.add(&self)
{
    if (self.first_freelist_node.has_value)
    {
        Handle handle = self.first_freelist_node.value;
        self.first_freelist_node = self.data[(usz)handle].freelist_node;
        self.data[(usz)handle] = { .item = {} };  // Replace freelist node by zero item.
        return handle;
    }
    else
    {
        self.data.push({ .item = {} });
        return (Handle)(self.data.len() - 1);
    }
}

fn Type* Pool.get_ref(&self, Handle handle)
{
    return &self.data[(usz)handle].item;
}

fn void Pool.remove(&self, Handle handle)
{
    self.data[(usz)handle].freelist_node = self.first_freelist_node;
    self.first_freelist_node = maybe::value{Handle}(handle);
}

module main;

import std;
import btree;
import pool;

typedef OrderId = long;

enum Side
{
    BID,
    ASK,
}
struct Order
{
    OrderId order_id;
    long price;
    long quantity;
    long entry_time_us;
    Side side;
}

fn int compare_order_id(OrderId a, OrderId b)
{
    switch {
        case a < b: return -1;
        case a > b: return 1;
        default: return 0;
    }
}

fn int compare_bid_by_priority(Order* a, Order* b)
{
    switch {
        case a.price > b.price: return -1;
        case a.price < b.price: return 1;
        default:
            switch {
                case a.entry_time_us < b.entry_time_us: return -1;
                case a.entry_time_us > b.entry_time_us: return 1;
                default: return compare_order_id(a.order_id, b.order_id);
            }
    }
}

// The only difference from `compare_bid_by_priority`
// is that lower ask price has bigger priority than higher ask price.
fn int compare_ask_by_priority(Order* a, Order* b)
{
    switch {
        case a.price < b.price: return -1;
        case a.price > b.price: return 1;
        default:
            switch {
                case a.entry_time_us < b.entry_time_us: return -1;
                case a.entry_time_us > b.entry_time_us: return 1;
                default: return compare_order_id(a.order_id, b.order_id);
            }
    }
}

alias OrderHandle = Handle{Order};

struct OrderBook
{
    Pool{Order} orders;
    BTree{OrderHandle} orders_by_id;  // All orders.
    BTree{OrderHandle} bid_by_priority;  // Only bid.
    BTree{OrderHandle} ask_by_priority;  // Only ask.
}

fn void OrderBook.init(&self, Allocator allocator)
{
    self.orders.init(allocator);
    self.orders_by_id.init(allocator);
    self.bid_by_priority.init(allocator);
    self.ask_by_priority.init(allocator);
}

fn void OrderBook.free(&self)
{
    self.orders.free();
    self.orders_by_id.free();
    self.bid_by_priority.free();
    self.ask_by_priority.free();
}

fn void OrderBook.add_order_to_by_priority_index(&self, OrderHandle handle) @local
{
    Order* order = self.orders.get_ref(handle);
    BTreeSlot{OrderHandle} slot;
    if (order.side == BID)
    {
        slot = self.bid_by_priority.@get_slot(; OrderHandle item_from_tree, int* x)
        {
            Order* cur_order = self.orders.get_ref(item_from_tree);
            *x = compare_bid_by_priority(order, cur_order);
        };
    }
    else
    {
        slot = self.ask_by_priority.@get_slot(; OrderHandle item_from_tree, int* x)
        {
            Order* cur_order = self.orders.get_ref(item_from_tree);
            *x = compare_ask_by_priority(order, cur_order);
        };
    }

    if (slot.existed) abort("Order already exists in by priority index");
    *slot.item = handle;
}

fn void OrderBook.remove_order_from_by_priority_index(&self, Order* order) @local
{
    if (order.side == BID)
    {
        bool removed = self.bid_by_priority.@remove(; OrderHandle item_from_tree, int* x)
        {
            Order* cur_order = self.orders.get_ref(item_from_tree);
            *x = compare_bid_by_priority(order, cur_order);
        };
        if (!removed) abort("Bid not removed");
    }
    else
    {
        bool removed = self.ask_by_priority.@remove(; OrderHandle item_from_tree, int* x)
        {
            Order* cur_order = self.orders.get_ref(item_from_tree);
            *x = compare_ask_by_priority(order, cur_order);
        };
        if (!removed) abort("Ask not removed");
    }
}

fn void OrderBook.add_or_update_order(&self, Order order)
{
    BTreeSlot{OrderHandle} slot = self.orders_by_id.@get_slot(; OrderHandle item_from_tree, int* x)
    {
        OrderId existing_order_id = self.orders.get_ref(item_from_tree).order_id;
        *x = compare_order_id(order.order_id, existing_order_id);
    };

    OrderHandle handle;
    Order* order_slot;  // Slot in the pool.
    if (slot.existed)
    {
        handle = *slot.item;
        order_slot = self.orders.get_ref(handle);
        // For simplicity we always reinsert order into a priority index.
        // More optimized solution would first check whether at least one
        // field which determines the priority has changed.
        self.remove_order_from_by_priority_index(order_slot);
    }
    else
    {
        handle = self.orders.add();
        *slot.item = handle;
        order_slot = self.orders.get_ref(handle);
    }

    *order_slot = order;
    self.add_order_to_by_priority_index(handle);
}

fn void OrderBook.remove_order(&self, OrderId order_id)
{
    OrderHandle handle;
    bool removed = self.orders_by_id.@remove(; OrderHandle item_from_tree, int* x)
    {
        OrderId existing_order_id = self.orders.get_ref(item_from_tree).order_id;
        *x = compare_order_id(order_id, existing_order_id);
        handle = item_from_tree;  // Note which handle was removed.
    };

    if (!removed) abort("Order not removed because it was not found");

    // At this point `handle` contains handle of the removed order.
    self.remove_order_from_by_priority_index(self.orders.get_ref(handle));

    self.orders.remove(handle);
}

fn Maybe{long} OrderBook.spread(&self)
{
    Maybe{OrderHandle} best_bid = self.bid_by_priority.first_item();
    Maybe{OrderHandle} best_ask = self.ask_by_priority.first_item();

    if (!best_bid.has_value || !best_ask.has_value) return {};
    Order* bid = self.orders.get_ref(best_bid.value);
    Order* ask = self.orders.get_ref(best_ask.value);
    return maybe::value{long}(ask.price - bid.price);
}

fn void print_tree(BTree{OrderHandle}* btree, Pool{Order}* pool)
{
    btree.@to_dot(io::stdout(); OrderHandle item_from_tree)
    {
        Order* order = pool.get_ref(item_from_tree);
        io::printf("id %d, px %d, h %d", order.order_id, order.price, item_from_tree)!!;
    }!!;
}

fn void main()
{
    OrderBook ob;
    ob.init(mem);
    defer ob.free();

    ob.add_or_update_order({
        .order_id = 1,
        .price = 10,
        .quantity = 4,
        .entry_time_us = 1,
        .side = BID,
    });
    ob.add_or_update_order({
        .order_id = 2,
        .price = 11,
        .quantity = 5,
        .entry_time_us = 2,
        .side = BID,
    });
    ob.add_or_update_order({
        .order_id = 3,
        .price = 14,
        .quantity = 5,
        .entry_time_us = 2,
        .side = ASK,
    });

    print_tree(&ob.orders_by_id, &ob.orders);
    print_tree(&ob.bid_by_priority, &ob.orders);
    print_tree(&ob.ask_by_priority, &ob.orders);
    assert(ob.spread().value == 3);

    // Order 1 improves price to jump over order 2.
    ob.add_or_update_order({
        .order_id = 1,
        .price = 12,
        .quantity = 5,
        .entry_time_us = 1,
        .side = BID,
    });

    assert(ob.spread().value == 2);

    // Remove best bid.
    ob.remove_order(1);

    assert(ob.spread().value == 3);

    // Remove remaining bid.
    ob.remove_order(2);

    assert(!ob.spread().has_value);
    assert(ob.orders_by_id.number_of_items == 1);
    assert(ob.bid_by_priority.number_of_items == 0);
    assert(ob.ask_by_priority.number_of_items == 1);
}
