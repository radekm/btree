## About the library

The `btree.c3l` library provides an implementation of a B-tree.
Its API is currently low-level, but straightforward.

The generic type `BTree` represents a B-tree instance. It is initialized using the `init` method
and freed using the `free` method.

The macros `@get_slot`, `@get_existing_slot`, and `@remove` are used to add, modify, and remove items.
These macros capture a trailing block that performs the comparison. This block receives `item_from_tree`
and pointer to an `int` for storing the comparison result:

- If the item being added, modified, or removed is less than `item_from_tree`,
  the comparison result should be negative.
- If it is greater than `item_from_tree`, the result should be positive.
- If it is equal, the result should be zero.

Macros with trailing blocks are used because C3 does not support closures,
and comparison logic may need access to variables from the surrounding environment.

This library is useful for building multiple indices over a pool of items.
The included example `order_book.c3` demonstrates this.
The pool `orders` contains orders from an exchange.
The `orders_by_id` index organizes these orders by `order_id`.
The `bid_by_priority` and `ask_by_priority` indices are partial - they include
only bid or ask orders, respectively - and organize them by `price`, `entry_time_us`, and `order_id`.

## Contributions

We accept:

- ✅ Bug reports for the following platforms:
  - macOS on arm64
  - Windows 11 on x64
  - Linux on x64

We don't accept:

- ❌ Pull requests
- ❌ Feature requests

## Notes on translation from Rust to C3

Rewrite of Rust's B-tree implementation to C3 for better clarity and safety.
Reviewing unsafe code in Rust is harder because rules (especially aliasing rules)
are more complex in Rust than rules in C or C3.

Code in C and C3 is usually shorter than code in Rust.
This is especially true for code in unsafe Rust.

`rust/node.rs` and `rust/remove.rs` are a copy of Rust's
`library/alloc/src/collections/btree/node.rs`
and `library/alloc/src/collections/btree/remove.rs`
from commit 810e4c1bc62a4801a4c29fe6c975630acbd78370.
`btree.c3l/node.c3` is `node.rs` translated to C3.
Comments were mostly preserved if they made sense in C3.
Code which made no sense in C3 was ignored. That was mostly

- Functions whose only purpose was to change phantom type parameters
  (marker parameters in case of `node.rs`).
  For example `NodeRef.borrow_mut`, `NodeRef.borrow_valmut` and `NodeRef.into_dying`
  have same body which does nothing and only differ in return type.
- Functions which when transalted to C3 became too simple.
